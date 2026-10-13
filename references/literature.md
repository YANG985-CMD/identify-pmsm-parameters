# 论文依据与扩展边界

10 篇题录于 2026-10-13 用 Crossref 核验，完整引用见 [references.bib](references.bib)。本实现为独立编写的积分最小二乘基线，不宣称复现某篇论文。各文献阅读层次不同。

| 文献 | 证据层次与实现用途 |
|---|---|
| Zhu, Liang & Liu, IEEE Access, 2021. *Online Parameter Estimation for Permanent Magnet Synchronous Machines: An Overview*. [DOI](https://doi.org/10.1109/ACCESS.2021.3072959) | 公开 PDF 重点段落；秩亏、病态和逆变器非线性约束 |
| Wang et al., CJEE, 2024. *Review of Inductance Identification Methods Considering Inverter Nonlinearity for PMSM*. [出版方](https://www.sciopen.com/article/10.23919/CJEE.2023.000046) | 摘要；电感随饱和/耦合变化，审查电压来源 |
| He et al., Sensors, 2026. *Online Multi-Parameter Identification for PMSM Parameter Monitoring Based on a ZOH Model and Dual-Sampling Strategy*. [全文](https://www.mdpi.com/1424-8220/26/3/1072) | XML 全文重点段落；SPMSM 等电感模型，ZOH+d轴注入+双采样+FFRLS，不能直接当成独立 Ld/Lq 算法 |
| Xiang et al., JMSE, 2025. *Online Parameter Identification for PMSM Based on Multi-Innovation Extended Kalman Filtering*. [出版方](https://www.mdpi.com/2077-1312/13/9/1660) | 正文片段；校准参数作初值、Q/R 试调，未知初值性能需另测 |
| Yang et al., Energies, 2018. *An Algorithm for Online Inertia Identification and Load Torque Observation via Adaptive Kalman Observer-Recursive Least Squares*. [出版方](https://www.mdpi.com/1996-1073/11/4/778) | 摘要及实验片段；J 与 TL 耦合、专门机械辨识条件 |
| Yang et al., IEEE TIE, 2025. *Parameter-Tuning-Free Two-Step Identification of Mechanical Parameters for PMSM Drives*. [摘要](https://ieeexplore.ieee.org/document/11083118/) | 摘要；机械两阶段设计候选，细节待全文复现 |
| Wang & Zhu, IEEE Access, 2026. *Overview of Online Parameter Identification of Permanent Magnet Synchronous Machines Under Sensorless Control*. [DOI](https://doi.org/10.1109/ACCESS.2026.3655929) | 题录/摘要线索；无位置传感器扩展参考，原文待精读 |
| Boileau et al., IEEE TIA, 2011. *Online Identification of PMSM Parameters: Parameter Identifiability and Estimator Comparative Study*. [DOI](https://doi.org/10.1109/TIA.2011.2155010) | 题录；可辨识性后续参考，原文待精读 |
| Liu et al., IEEE TIE, 2011. *Online Multiparameter Estimation of Nonsalient-Pole PM Synchronous Machines With Temperature Variation Tracking*. [DOI](https://doi.org/10.1109/TIE.2010.2054055) | 题录；温度跟踪后续参考，原文待精读 |
| Zhou et al., CMC 2023 卷期. *Double Update Intelligent Strategy for Permanent Magnet Synchronous Motor Parameter Identification*. [全文](https://www.techscience.com/cmc/v74n2/50293/html) | 正文；WDE+PSO，增加激励后优化，验证主要为仿真，逆变器非线性留作后续 |

## 扩展选择

- 在线 RLS：先有可信基线和信息量判断，弱信息段暂停更新；内部矩阵不直接解释为真实参数置信区间。
- EKF/MIEKF：相同数据和先验下比较多初值、Q/R、延迟/噪声、独立工况和算力；历史残差相关性需正确处理。
- J/B：可信转矩尺度、稳速/加减速和明确负载假设。任意未知 TL 下不承诺同时唯一辨识；滑行曲线通常只约束摩擦/惯量比值。
- PSO/DE：用于有必要的非线性模型/目标；当前线性回归不因群智能优化获得额外信息。

## 官方交叉验证

[测量数据参数化](https://www.mathworks.com/help/simscape-electrical/ug/parameterize-a-pmsm-from-measurements.html)、[自定义硬件](https://www.mathworks.com/help/mcb/gs/estimate-pmsm-parameters-using-custom-hardware.html)、[STM32 示例](https://www.mathworks.com/help/stm32b/ug/stm32-parameter-estimation.html)、[运行时估计](https://www.mathworks.com/help/mcb/gs/run-time-parameter-estimation-pmsm-sensor-feedback.html)。核对本地版本、许可、编码器/观察器及指定板卡条件，不把官方示例成功等同于用户硬件通过。
