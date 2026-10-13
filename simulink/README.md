# 标准模块 PMSM 参数辨识仿真

验证日期：2026-10-13；实际运行环境：MATLAB / Simulink R2024b。模型为 [pmsm_id_bench.slx](pmsm_id_bench.slx)，仅使用标准 Simulink 模块；FFNN 的训练和推理采用基础 MATLAB 数组运算。无需自定义模块库、Simscape、Motor Control Blockset、Deep Learning Toolbox 或 Embedded Coder。其他版本尚未验证。

这套仿真回答：当 dq 指令电压与电机实际电压不一致时，同一个四参数辨识算法会受到多大影响；使用独立电压误差标定后能否改善，并能否识别标定漂移和信息不足。

## 运行方式

MATLAB 当前目录设为仓库根目录。查看并直接运行默认模型：

```matlab
open_system(fullfile(pwd,'simulink','pmsm_id_bench.slx'));
```

默认 `bench` 参数已经保存在模型工作区，点击 Run 即可运行 0.6 s。直接运行展示电流和电压信号；完整辨识和比较由以下运行器完成：

```matlab
addpath(fullfile(pwd,'simulink'));
report = pmsm_run_simulink_benchmark(fullfile(pwd,'output','benchmark_demo'));
assert(report.allChecksPassed);
```

结果目录必须是一个新目录。运行器临时加入所需函数路径，结束时恢复其修改前的路径和 Simulink 文件生成设置，保留模型窗口。示例中的 `addpath` 只影响当前会话。

项目有临时目录约定时，运行前用 `setenv('PMSM_SKILL_TMPDIR',任务临时目录)` 指定。运行器将缓存与生成目录放到该位置；未指定时使用系统临时目录。结果目录是交付位置，需与临时缓存区分。直接点击 Run 使用当前 MATLAB 的缓存配置；有约定时先配置相应缓存目录。

运行器输出：

| 文件 | 内容 |
|---|---|
| `benchmark_summary.csv` | 六组参数、相对误差、独立预测误差、秩与条件数 |
| `benchmark.json` | 参数真值、仿真设置、随机种子、模型 SHA-256、检查及适用范围 |
| `benchmark-data.mat` | 原始采样、估计、验证、标定网络，可用于重新分析 |
| `calibration.csv` / `voltage-network.json` | 独立合成标定点和网络参数 |
| `benchmark-comparison.png` | 参数误差、电流预测误差、标定和独立预测曲线 |

仓库保存轻量参考结果与图，原始 MAT 在本地运行时生成，默认不纳入 Git。

## 模型与信号

![模型总览](reference-results/model-overview.png)

- `Excitation`：多频 dq 电压激励，给定电角速度并积分得到电角度。
- `AverageInverter`：dq 电流变换到三相，用平滑电流相关电压误差表示逆变器偏差，再变换回 dq 并从指令电压中扣除。
- `PMSMPlant`：使用 Gain、Sum、Product、Integrator 等标准模块表达常参数 PMSM 电气方程。
- `SampledTelemetry`：同步采样电流、指令/实际电压、速度和角度。Root Outport 输出 Dataset；Scope 用于查看。

幅值不变 dq、d 轴沿永磁磁链，模型为：

$$
\frac{di_d}{dt}=\frac{u_d-R_s i_d+\omega_e L_q i_q}{L_d},\qquad
\frac{di_q}{dt}=\frac{u_q-R_s i_q-\omega_e(L_d i_d+\psi_f)}{L_q}.
$$

平均相电压误差使用明确的合成关系：

$$
\Delta v_x = V_{\mathrm{drop}}\tanh(i_x/I_0)+R_{\mathrm{drop}} i_x,\quad x\in\{a,b,c\}.
$$

三个相位共用同一条对称曲线。这是可控的非线性误差模型，未包含开关波形、母线纹波、驱动延时或三相器件不一致。

| 设置 | 默认值 |
|---|---|
| Rs / Ld / Lq / 永磁磁链 | 0.7 Ω / 4 mH / 6 mH / 0.03 Wb |
| 电压误差模型 | Vdrop = 0.35 V，Rdrop = 0.03 Ω，I0 = 0.15 A |
| 求解器 / 步长 / 时长 | 固定步长 ode4 / 10 μs / 0.6 s |
| 同步采样 | 100 μs，即 10 kHz；这不是 PWM 开关频率 |
| d 电压 | 1.2 + 0.8 sin(2π·31t + Phase) + 0.35 sin(2π·9t) V |
| q 电压 | 5 + 1.1 sin(2π·17t + π/2 + Phase) + 0.6 sin(2π·4t) V |
| 电角速度 | 160 + 40 sin(2π·3t + Phase) rad/s |
| 辨识 / 独立验证 | 训练激励 Phase = 0，另一独立仿真 Phase = 0.8 rad |
| 回归窗口 | WindowSamples = 10；约 1 ms 积分窗口 |

默认配置在 [pmsm_bench_defaults.m](pmsm_bench_defaults.m)，运行器用 SimulationInput 覆盖各情景的模型工作区参数。只修改默认函数不会自动改动已保存模型的默认工作区；通过运行器或 `pmsm_simulate_bench` 执行时会使用传入的配置。

## FFNN 标定与辨识

标定使用另外生成的 81 个相电流—电压误差点，覆盖 −8 至 +8 A，零点附近更密，加入 1 mV 标准差噪声。单输入、5 个 tanh 隐藏单元、单输出网络采用 Adam 训练；固定随机种子、3 次初始权重重启。训练不使用电机 Rs/Ld/Lq/磁链真值或辨识误差作为标签。

网络在 500 个未用于训练的电流点上检查误差。这里的标定和测试标签都来自合成模型，不能代替实际相电压标定。真实平台需要另外取得同一逆变器、母线电压与温度条件下的标定数据，并验证每相差异。

`pmsm_compensate_record` 从采样 dq 电流和角度恢复相电流，用网络预测三相误差，再经 Clarke/Park 变换修正用于辨识的 dq 电压。它只接受仿真中的原始指令电压，拒绝重复补偿；网络推理拒绝超出标定电流范围。补偿没有写入逆变器门极命令。

参数计算仍调用仓库原有的 `pmsm_identify_electrical` 积分加权最小二乘。真值只用于事后计算仿真误差，只有 `actual_voltage_oracle` 对照行会直接使用电机端真实仿真电压；这行用于诊断算法，不代表实机可取得同等电压质量。

## 已运行的六组结果

参数列为有符号相对误差百分数，电流列为另一组激励的 d/q 电流 RMSE。真值如上表。完整精度见 [CSV](reference-results/benchmark_summary.csv) 和 [JSON](reference-results/benchmark.json)。

| 情景 | Rs 误差 % | Ld 误差 % | Lq 误差 % | 磁链误差 % | d / q RMSE（A） | 预测检查 |
|---|---:|---:|---:|---:|---|---|
| 理想逆变器 | 0.000084 | −0.000380 | −0.000103 | 0.000049 | 0.0000189 / 0.0000107 | 通过 |
| 非线性逆变器，直接用指令电压 | 37.9128 | 2.2678 | 3.6843 | −1.4329 | 0.12851 / 0.06123 | 未通过 |
| 非线性逆变器，真实电压诊断对照 | 0.000217 | −0.001216 | −0.000563 | 0.000136 | 0.0000235 / 0.0000156 | 通过 |
| FFNN 独立标定补偿 | −0.017895 | −0.001702 | −0.006258 | 0.001627 | 0.000209 / 0.000138 | 通过 |
| 补偿＋采样噪声 | −0.008951 | −0.245787 | −0.229122 | 0.018877 | 0.005119 / 0.005238 | 通过 |
| Vdrop 漂移至 0.5 V，仍用原标定 | 15.8183 | 0.6208 | 1.8514 | −0.5189 | 0.06508 / 0.03080 | 未通过 |

噪声行的电流/指令电压噪声标准差分别为 5 mA / 5 mV。参考结果的 FFNN 标定训练 RMSE 为 1.043 mV，未参与训练的电流点 RMSE 为 0.829 mV。不同 MATLAB 版本可能出现小幅数值差异。

![比较图](reference-results/benchmark-comparison.png)

本仿真的电流预测阈值为每轴 0.05 A，仅用于合成测试。六行回归矩阵均为秩 4，归一化条件数约 1.85–2.03；未补偿和旧标定仍出现较大偏差，说明“有足够秩”并不保证电压质量或参数精度。

运行器还检查：理想/真实电压对照的最大参数误差、补偿后误差和改善幅度、补偿后独立预测、带噪声误差、标定漂移退化、无激励拒绝、求解步长敏感性，共 **10/10 项通过**。无激励实验从精确稳态初值开始，返回 `not_identifiable`；求解步长减半时，d/q 电流波形差异约 6.6×10⁻¹³ / 6.0×10⁻¹³ A。本结果只支持当前模型与步长设置。

原有 MATLAB 的 **28 项测试通过**。辨识结果仍保留候选状态，独立预测状态单独报告；不自动作为控制器参数。

## 与论文的对应关系及范围

FFNN 电压误差补偿思路参考 Xiang、Zhou、Wang，*Online Parameter Identification for Sensorless PMSM Drives with Inverter Nonlinearity Compensation*，Electronics 2026，15(12), 2722，[出版方原文](https://www.mdpi.com/2079-9292/15/12/2722)。其真实 STM32F407 台架的核验记录见 [先进论文清单](../references/hardware-validated-papers.md)。

原论文结合高频 d 轴注入、在线 Rs/Ld 辨识和无位置传感器控制。本包独立编写了小型网络和标准模块电气模型，用已有离线四参数基线检查补偿原理。它没有复现论文的完整控制流程，也没有对不同论文算法作优劣排名。

当前范围是固定参数、给定速度/角度的平均电压电气模型。尚未覆盖机械负载闭环、FOC 控制器、PWM 开关、ADC 延时/量化、角度估计误差、磁饱和、交叉饱和、热漂移或 MCU 执行时间。加入噪声的一行是一个指定噪声水平下的单次实验，不能据此声称所有噪声条件都鲁棒。

实物应用的下一步是用实际逆变器标定替换合成标定，接入已核对的同步采样，保留独立实验和物理参数对照，再逐项增加时序、位置误差和闭环控制验证。
