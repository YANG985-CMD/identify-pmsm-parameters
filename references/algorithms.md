# 积分最小二乘与独立验证

局部常参数、正弦反电势模型：

\[
u_d=R_s i_d+L_d\dot i_d-\omega_e L_qi_q,\qquad
u_q=R_s i_q+L_q\dot i_q+\omega_e(L_di_d+\psi_f).
\]

各窗口积分后除以持续时间，未知向量为 `[Rs,Ld,Lq,psi_f]`：

\[
\frac{1}{\Delta t}\begin{bmatrix}\int u_d dt\\\int u_q dt\end{bmatrix}
=\frac{1}{\Delta t}\begin{bmatrix}
\int i_d dt&\Delta i_d&-\int\omega_e i_qdt&0\\
\int i_q dt&\int\omega_e i_ddt&\Delta i_q&\int\omega_e dt
\end{bmatrix}\theta.
\]

梯形积分用真实时间戳，不直接差分电流，不跨无效行/间断/段边界。SPMSM 合并 Ld/Lq 列为 `[Rs,L,psi_f]`，IPMSM 分别估 Ld/Lq。

## 求解选项

| 选项 | 默认 | 用途 |
|---|---|---|
| Model | ipmsm | ipmsm / spmsm |
| WindowSamples | 20 | 时间间隔数，实际含 21 个端点样本 |
| StrideSamples | 0 | 0 取窗口长度，否则为窗口起点步长 |
| Fixed | 空 struct | IPMSM 可固定 Rs/Ld/Lq/psi_f；SPMSM 可固定 Rs/L/psi_f |
| EquationStd | [1,1] | 窗口 d/q 电压残差相对标准差，按倒数加权 |
| MaxCondition | 1e6 | 归一化矩阵条件数上限，不是通用精度保证 |

先扣除固定先验贡献，再以列二范数归一化自由列，用 SVD 查秩及条件数，合格后反斜杠求最小二乘。不显式求逆，零列不创造信息。weakDirectionScaled 在归一化未知量空间，需结合 columnScales 解读。

静止数据对磁链无信息，可在独立实验已给可信磁链时使用 `Fixed=struct('psi_f',knownFlux)`。恒速 id=0 且有可信 Rs/Ld 时可只识别 Lq/磁链；固定值保留为先验，不能称为识别结果。固定参数错误会传递到估计中。

| status | 处理 |
|---|---|
| estimated_unvalidated | 有限正值候选，需独立验证与物理证据 |
| not_identifiable | 秩亏或方程不足，自由参数 NaN，补充激励/工况 |
| ill_conditioned | 满秩但条件数过大，自由参数 NaN，改善数据 |
| nonphysical | 有非正/非有限参数，保留诊断，不裁剪伪装成功 |
| prior_only | 全部参数固定，没有参数被辨识 |

低残差不证明唯一性。两条单时刻方程不意味着动态数据永远只能辨识两个参数；同一稳态重复记录也不自然增加独立信息。

## 验证

`pmsm_validate_electrical` 用独立电压/电角速度驱动微分模型，以每个连续实验段首个实测电流作种子，ode45 连续预测；不在每窗口重置，种子不计分。输入使用线性插值，不是精确 PWM 模型；ZOH/开关纹波/延迟明显时须匹配预测模型后再判读。

报告电流 RMSE（A）、按实测电流标准差归一化的 RMSE、计分样本及连续段。默认 `MaxRMSE=[Inf,Inf]` 只报告 metrics_only。给两个有依据的有限阈值后输出 prediction_check_passed/failed，仍不自动承诺物理参数真值精度或改变控制器。

该实现没有自动死区补偿、稳健损失、时间延迟辨识、磁饱和图、工具变量、总最小二乘或参数置信区间。积分降低差分噪声但不消除变量误差偏差。窗口共享端点或重叠产生相关误差，EquationStd 不等于 ADC 单点噪声。强饱和/温漂要分工况估计。

对指令电压、未经核验位置和时间对齐保持明确警告。仿真验证仅证明数值流程行为，不提供用户真实电机参数、实机精度或板卡兼容性。
