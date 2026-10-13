---
name: identify-pmsm-parameters
description: Identify PMSM or FOC brushless-motor electrical and mechanical parameters using MATLAB. Extract motor-manual information, import PMI1 telemetry, estimate Rs/Ld/Lq/PM flux or staged J/viscous B/Coulomb friction from credible torque and speed, and validate independent experiments. Includes standard-block electrical and mechanical Simulink benches. Use for 电机参数辨识、实机采样接入、电阻电感磁链、转动惯量与摩擦辨识. PI/TD3 tuning and standalone state observation are separate tasks.
---

# 永磁电机参数辨识

将真实采样或明确标记的仿真数据转成可审查的参数候选。包含离线电气辨识、机械 J/B/Tc 分阶段辨识、独立电流/速度预测，以及不依赖特定 HAL 的 PMI1 采样接口。MATLAB 使用基础功能与 JVM，已在 R2024b 测试。在线 RLS/EKF、非线性摩擦观测器和板端自动实验控制尚未实现；通用接口不表示已在某块板卡上通过实测。

用户要求转动惯量 J、机械摩擦 B/Tc 或速度预测时，先读 [机械辨识](references/mechanical-identification.md)，使用下文机械路线；电气参数请求使用 dq 电气路线。只有速度信号不能自动得出绝对 J/B。

## 数据与适用性

用户可以先提供电机手册、数据表或铭牌图片，无需先手填全部参数。有这些资料时读 [手册信息提取](references/manual-intake.md)，先核对具体型号/版本，提取参数、原始单位、条件与页码，输出“已找到、可明确换算、待补充”的信息表。可继续从已提供的控制板资料和本地固件提取接口配置，只追问影响接入或辨识的缺项与冲突。手册标称值保留为资料参考，不冒充辨识结果或实测校准；没有依据时不能填完整实验的电压来源、角度来源或时序已验证状态。

读取 [数据约定](references/data-contract.md)。优先从已有文件、配置及项目代码确定电机类型、极对数、变换和单位、实际采样率、电压来源、角度来源、可用实验段。只追问影响可辨识性或实验路线的缺失信息。

- 必需反馈量为 `t, id, iq, ud, uq, omega_e`；接受 CSV、MAT 或 table。参考电流不能替代实际电流。
- 显式转换到 SI 单位、幅值不变 dq、d 轴沿永磁磁链。机械 rpm 转电气 rad/s 需要可信极对数。不猜峰值/有效值、线量/相量或标幺基值。
- 检查角度零偏、相序、ADC 校准、电压/电流滤波延迟。程序检查元数据声明，不能证明传感器或单位标签正确。
- 只有速度环日志时，说明不能据此辨识完整电参数，并提出补采信号。FOC 不保证反电势正弦，需检查常参数 dq 模型适用性。

## 计算、验证与交付

需要接实物或已有板端原始记录时，先读 [通用实机数据接入](references/hardware-integration.md)。现有 SI dq CSV 可直接辨识；新板可适配 `firmware/pmsm_capture.h/.c`，用 `scripts/pmsm_capture.py decode` 回放或 `serial` 限时接收，再用 `pmsm_identify_capture` 核对记录哈希并运行完整辨识/独立验证。Python 离线解码仅需标准库，串口接收另需 pySerial。

运行串口接收前先取得现有采集授权并核对端口、DTR/RTS 的板级影响。接收程序不发电机命令，结束接收也不会停止电机。不要把未知固件当成已实现 PMI1，不能猜换算系数、电压来源或位置零点。当前没有内置 CAN 接收/重组适配。

读取 [算法及失败处理](references/algorithms.md)。实际参数必须由 MATLAB 计算，不能用铭牌或语言推断冒充辨识结果。

1. 将本 skill 的 `scripts` 目录加入当前 MATLAB 会话路径，不永久修改路径。通过 MATLAB MCP 检查版本并执行。保留用户已有变量，使用任务专属变量名。
2. 用 `pmsm_audit` 检查字段、单位、时间顺序和有效样本。无效行、饱和、时间间断和实验段切换作为边界，不插值跨过边界。
3. 选择 `Model="ipmsm"`，或有证据支持等电感的 `Model="spmsm"`，运行 `pmsm_identify_electrical`。对窗口长度做敏感性比较，避免平均抵消激励。
4. 审查秩、归一化条件数、残差和物理范围。`not_identifiable` / `ill_conditioned` 时说明补采工况，不用正则化、参数边界或复杂优化器声称恢复唯一参数。`Fixed` 只接受有来源的先验，报告先验误差影响。
5. 用另一实验的 ID 和原始记录执行 `pmsm_validate_electrical`。文件改名不构成独立数据，不随机拆分相邻样本冒充独立实验。
6. `MaxRMSE` 应由控制需求、测量精度或用户标准确定。未给阈值时只报告指标。预测通过不证明参数真值精度，仿真通过不等于实机通过。
7. 用 `pmsm_export` 输出新目录。报告参数、单位、固定/估计来源、工况、设置、警告、秩/条件数及独立验证。默认保持候选身份，正式控制器写入需有物理证据及用户任务授权。

调用示例：`skillFolder` 指向本文件所在目录，数据和元数据按数据约定准备。

```matlab
previousPath = path;
pathCleanup = onCleanup(@() path(previousPath));
addpath(fullfile(skillFolder,'scripts'));
estimate = pmsm_identify_electrical(trainData,trainMeta, ...
    Model="ipmsm",WindowSamples=20);
% Continue only for status == "estimated_unvalidated".
validation = pmsm_validate_electrical(estimate,holdoutData,holdoutMeta);
% Add MaxRMSE=[idLimit,iqLimit] only when the limits have a stated basis.
pmsm_export(estimate,validation,resultFolder);
```

没有数据时可运行 `pmsm_simulated_experiment`，结果必须标为“仿真验证”，不能称为用户电机辨识。MATLAB 回归见 `tests/pmsmIdentificationTest.m` 和 `tests/pmsmCaptureIntegrationTest.m`；协议及接收器测试见 `tests/test_capture.py`。有用户或项目临时目录约定时，运行前将环境变量 `PMSM_SKILL_TMPDIR` 设为符合约定的任务目录。测试在该目录下创建独立子目录；未设置时使用系统临时目录。

用户要求 Simulink 验证或比较电压误差补偿时，读 [仿真包说明](simulink/README.md)，使用 `simulink/pmsm_id_bench.slx` 和 `pmsm_run_simulink_benchmark`。需要 MATLAB、Simulink 与 JVM，标准模块即可。默认模型参数保存在模型工作区，运行器按情景显式覆盖；缓存遵守 `PMSM_SKILL_TMPDIR`，结果写新目录。先检查 10 项验证及失败案例，再报告误差与工况。FFNN 使用独立合成标定，不接真实硬件；不得把该网络直接当作任意逆变器的补偿。改模型时遵循可用的 Simulink 建模工具及库配置。

## 实验与扩展

### 机械参数 J、B 和 Tc

机械输入为 `t, omega_m, torque_e`，有实测负载时再加 `load_torque`。核对转矩尺度、机械速度单位、负载状态、配置 ID 和惯量范围；B 是黏性摩擦，不表示所有阻力。用 `pmsm_identify_friction` 从已知负载的多速度稳速段得到 B/Tc，再用 `pmsm_identify_mechanical` 在另一加减速记录积分拟合 J。动态负载已知时直接扣除；明确未知恒定负载时可同时估一个训练负载常数，不支持任意未知变化负载。

已有 dq / PMI1 table 可经 `pmsm_mechanical_from_dq` 用可信极对数与电气候选计算 Te/机械速度，保留磁阻转矩、无效边界和尺度来源。电气参数的误差会传播，不能把指令电流/指令转矩或输出轴传感器读数未经力矩平衡直接当成 Te。

用第三组已知负载实验执行 `pmsm_validate_mechanical`，速度误差阈值单位 rad/s，未提供时只报告指标。分别审查摩擦段与 J 的秩/条件数、速度变化和预测；共同转矩尺度错误可能预测通过，仍需校准证据。`pmsm_export_mechanical` 导出新目录，明确转子惯量或包含附件/负载的总惯量。不自动写 PI 参数或执行实机激励。

机械仿真读 [机械台架说明](simulink/mechanical-README.md)，运行 `pmsm_run_mechanical_benchmark`。模型含电流状态、PMSM 转矩、J/B/Tc 和速度/角度状态，转速由转矩产生；只用标准模块。它是简化电流环的刚性轴仿真，没有完整开关或高级论文观测器。回归在 `tests/pmsmMechanicalTest.m`。

筛选用于实机扩展的先进算法时，优先读 [先进论文与实物实验核验](references/hardware-validated-papers.md)。区分已核对真实台架、只有摘要实验声明、纯仿真与硬件在环；记录电机/控制器、反馈与采样条件、参数误差基准和模型边界。不能把读过论文说成已在本项目复现，也不能把不同工况或编码器/无位置传感器结果混在一起比较。

读取 [论文依据](references/literature.md) 后选扩展。静止多电平数据用于 Rs；已知轴向的动态数据用于 Ld/Lq；多速度/负载或开路反电势用于磁链。通过 `Fixed` 支持只估有信息支持的子集。实机自动激励和通用电压补偿尚未实现；仿真中的 FFNN 补偿仅用于可复现的原理验证。

机械辨识需要可信转矩尺度、加减速和负载/摩擦假设。在线算法应在 MCU 或实时目标确定性执行。首版不发送串口/CAN 指令、不刷写固件、不启动电机。用户要求实机扩展时，先检查真实驱动协议和已授权实验范围，再实现可审查的采集与控制逻辑。

临时文件遵守用户或项目约定，在指定临时根目录下建立独立任务目录；没有约定时才使用系统临时目录。正式结果写用户指定位置。清理本任务不再需要的临时文件；工具拒绝时说明残留路径与拒绝原因，不尝试绕过。
