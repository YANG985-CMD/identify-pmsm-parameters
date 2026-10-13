# PMSM 机械参数辨识：J、B 和库仑摩擦

本模块实现离线分阶段辨识与独立速度预测，数值由 MATLAB 计算。输出 J 为电机轴侧声明的惯量，B 为黏性摩擦系数，Tc 为库仑摩擦转矩。带联轴器、齿轮或负载时，通常识别的是折算到电机轴的总惯量。三组记录必须来自同一机械配置，实验 ID 不同；相同数字记录改名仍会被拒绝。

## 模型与分阶段算法

采用远离零速的刚性单惯量模型：

\[
T_e=J\dot\omega_m+B\omega_m+T_c\operatorname{sgn}(\omega_m)+T_L.
\]

正号定义为正向旋转方向：Te 为电磁转矩，TL 为从 Te 中减去的外部负载转矩，可正可负。输出轴转矩传感器读数通常不能直接当成 Te；应结合其安装位置建立转矩平衡。

第一阶段 `pmsm_identify_friction`：使用已知零负载或实测负载下的多个稳速段，以 `[mean(omega_m), sign(omega_m)]` 拟合 B/Tc。每段至少 3 个样本、默认持续时间 0.15 s；速度线性趋势默认不超过 0.2 rad/s²，速度跨度默认不超过 0.5 rad/s。阈值需按仪器和工况调整。单个速度点不能唯一分开 B 与 Tc。建议采集正反向、多速度数据检查摩擦对称性。

第二阶段 `pmsm_identify_mechanical`：固定第一阶段得到的 B/Tc，在加减速窗口积分：

\[
\int_{t_1}^{t_2}(T_e-T_L-B\omega_m-T_c\operatorname{sgn}\omega_m)dt
=J[\omega_m(t_2)-\omega_m(t_1)].
\]

默认窗口为 40 个采样间隔，窗口间不重叠，采用真实时间戳的梯形积分。矩阵列归一化后用 SVD 检查秩、条件数，再最小二乘求解；默认条件数上限为 10⁶。所有有效窗口速度变化都小于默认 0.2 rad/s 时返回 `not_identifiable`，不把噪声产生的微小变化解释为 J 信息。

若动态实验的负载明确为一个未知常数，`load_model="constant_unknown"` 同时拟合 J 和一个有符号负载转矩，仍需足够不同的加速度。这个常数仅属于训练实验，不代表下一次实验的负载。任意未知变化负载不在首版支持范围；把变化负载错误声明为常数可能造成偏差，不能保证程序从声明中发现所有错误。

第三阶段 `pmsm_validate_mechanical`：使用另一组已知零负载或实测负载记录，由 Te/TL 驱动速度微分方程。每个连续、同方向有效段只用起点速度初始化，起点不计入误差；不逐样本重新使用测量速度。默认只报告 RMSE，传入有依据的 `MaxRMSE` 才判定通过/失败，单位为机械 rad/s。

`pmsm_export_mechanical` 写入新的结果目录，包含参数 CSV、预测速度 CSV、MAT、元数据、两阶段诊断和数据指纹 JSON。B/Tc 标注为另一稳速试验得到，J 标注为动态积分得到；不写控制器。

## 数据和元数据

CSV、含 `data` table 的 MAT 或 table 输入均可。

| 列 | 单位 | 含义 |
|---|---|---|
| t | s | 严格递增时间 |
| omega_m | rad/s | 实际机械速度，电角速度必须先除以可信极对数 |
| torque_e | N*m | 可信电磁转矩，参考指令不能替代实际转矩 |
| load_torque | N*m | `load_model="measured"` 时必需的轴侧实际外负载 |
| segment | 整数，可选 | 不同稳速段/实验段边界 |
| valid / saturated | 0/1，可选 | 排除无效/饱和样本，保留边界 |

时间间断超过中位采样间隔 3 倍、转向变化、实验段变化和无效行都是积分/预测边界。默认 `MinSpeed=2` rad/s，排除低速静摩擦区。不是所有电机都适合此阈值；若 Stribeck、齿槽、柔性轴或方向不对称明显，应扩展模型。

必需元数据：`experiment_id`、同配置的 `configuration_id`、`source_kind="measurement"/"simulation"`、`experiment_type="friction_steady"/"mechanical_dynamic"`、`time_alignment="verified"`、`shaft_reference="motor"`、`inertia_scope="rotor_only"/"motor_and_attached_load"`、`friction_model="viscous_coulomb_sign"`、`speed_source`、`torque_source`、`torque_scale_evidence`、`load_model` 和上表单位。

`speed_source` 接受 encoder、hall_interpolated、sensorless 或 simulation。实际估算速度的滤波延迟、低速分辨率与角度偏差需要另审查。`torque_source` 接受 calibrated_electromagnetic、dq_model 或 simulation；不接受指令。`load_model` 为 known_zero、measured 或 constant_unknown。known_zero/constant_unknown 数据应省略 load_torque，避免静默丢弃一列真实负载。

模板见 [mechanical-meta.example.json](../assets/mechanical-meta.example.json)。模板内未知项保持未知，不能靠改标签证明校准或空载状态。机械配置 ID 的一致也只是声明，不能证明实际附件未变化。

## 复用 PMI1 / dq 数据

对幅值不变 dq、d 轴沿永磁磁链的已确认 PMSM 模型：

\[
\omega_m=\omega_e/p,\qquad
T_e=\tfrac32p[\psi_f i_q+(L_d-L_q)i_di_q].
\]

`pmsm_mechanical_from_dq(dqData,dqMeta,electricalCandidate,polePairs,mechanicalMeta)` 用原来的 SI dq table 计算机械输入，保留无效、饱和和段边界，并记录电气候选参数和指纹。IPMSM 保留磁阻转矩项，不默认 id=0。已有 PMI1 解码 table 可复用，但接收器和 `pmsm_identify_capture` 不会自动运行机械实验或采集负载传感器。

转换前需验证电流和速度时间对齐；真实数据不能用仿真电气参数来认证 Te。电气候选仍有不确定性，不能把转矩计算视为独立转矩标定。机械电磁转矩无需 ud/uq 字段，但此 dq 转换工具复用现有电气数据审查，要求完整的电气 table。

## 调用示例

```matlab
addpath(fullfile(skillFolder,'scripts'));
friction = pmsm_identify_friction(steadyData,steadyMeta);
candidate = pmsm_identify_mechanical(dynamicData,dynamicMeta,friction);
% 两阶段均须得到 estimated_unvalidated 才继续。
validation = pmsm_validate_mechanical(candidate,holdoutData,holdoutMeta);
pmsm_export_mechanical(candidate,validation,newResultFolder);
```

稳速段选择、实际转矩尺度、空载或负载证据以及机械配置由实验决定。只有恒速、只有速度、只有电流指令，或只有滑行曲线但摩擦与转矩尺度全未知时，不承诺 J/B 唯一识别。

## 论文依据与实现边界

- Jing et al., *Energies* 14(1), 166 (2021), **A Novel Moment of Inertia Identification Strategy for Permanent Magnet Motor System Based on Integral Chain Differentiator and Kalman Filter**。[原文](https://www.mdpi.com/1996-1073/14/1/166)，DOI 10.3390/en14010166。已核对索引正文实验章节：6 kW SPMSM、DSP/FPGA、编码器与负载电机；先识别 B/Tc 再识别 J。本模块参考分阶段和负载分离思路，没有复现其积分链微分器或卡尔曼滤波器。
- Liu & Zhu, *IEEE TCST* 25(5), 1816–1824 (2017), **Fast Determination of Moment of Inertia of Permanent Magnet Synchronous Machine Drives for Design of Speed Loop Regulator**。[作者全文](https://eprints.whiterose.ac.uk/id/eprint/124462/8/pdf%20of%20final%20paper.pdf)，DOI 10.1109/TCST.2016.2615090。已读取作者全文的实物章节，包含 PMSM、直流负载电机、dSPACE、编码器；其等效摩擦项包含更多损耗，不能直接作为纯 B 的参考真值。
- Yang et al., *IEEE TIE* 72(12), 12378–12392 (2025), **Parameter-Tuning-Free Two-Step Identification of Mechanical Parameters for PMSM Drives**。[作者机构记录](https://research.polyu.edu.hk/en/publications/parameter-tuning-free-two-step-identification-of-mechanical-param/)，DOI 10.1109/TIE.2025.3577312。核对到摘要报告 1.2 kW 实物实验、非线性/不对称摩擦及在线惯量/负载估计；全文实验细节未完整复核。作为后续高级路线，不宣称已实现论文算法。

[MathWorks 参数化示例](https://www.mathworks.com/help/simscape-electrical/ug/parameterize-a-pmsm-from-measurements.html)也采用稳速摩擦与滑行惯量分项试验，但页面明确其数据由已知参数仿真产生，不能当成本项目实物验证。[官方机械估计块](https://www.mathworks.com/help/mcb/ref/pmsmmechanicalparameterestimator.html)属于 Motor Control Blockset，本项目没有使用它。

本项目自身证据为 27 项机械软件回归及 [标准模块仿真](../simulink/mechanical-README.md)，目前没有新增实物测试。共同转矩尺度偏差会使 J/B/Tc 同比例偏移，即使速度预测通过也不证明绝对参数正确。
