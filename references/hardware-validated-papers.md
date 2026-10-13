# 先进参数辨识论文：实物实验核验

检索与核验日期：2026-10-13。范围为 PMSM/FOC 无刷电机的电气参数辨识，重点关注 2025–2026 年工作；不是穷尽性系统综述。

完整题录见 [references.bib](references.bib)。本轮添加 7 条题录：4 篇新增已核验实物论文、3 篇待核验候选；另有 1 篇已核验实物论文沿用首轮题录。

入选条件：读取到原论文实验章节，并能核对真实电机/发电机、控制器、实验图表及工况。纯仿真、纯硬件在环和只读到摘要的文章不列入下面的已核验清单。题录与 DOI 用 Crossref 核对；ResearchGate 仅用于读取作者上传的原论文全文，不采用平台自动摘要或推荐内容。

相较当前离线积分最小二乘，这些方法的价值主要在于逆变器误差补偿、数字控制时序建模、无位置传感器耦合消除和实验激励设计。它们的台架结果不证明在所有控制板和电机上都优于现有基线。

## 已确认真实台架的 5 篇

### 1. 虚拟信号注入与全参数估计：IEEE JESTPE，2025

Wang, Zhu & Liang. *Virtual Signal Injection-Based Online Full-Parameter Estimation of Surface-Mounted PMSMs Without Influence of Position Error and Inverter Nonlinearity*. 13(2), 2341–2357. [DOI](https://doi.org/10.1109/JESTPE.2025.3544820)；[作者上传原文](https://www.researchgate.net/publication/389292891)。

- 原文 IV 节、图 14–25：SPMSM 与 IPMSM 原型、dSPACE DS1006，5 kHz 控制/开关频率；SPMSM 有 40 和 5 r/min 实验。
- 在观察器中注入虚拟信号，构造削弱位置误差和逆变器误差影响的模型。参考电阻/磁链来自 LCR/拖动反电势，电感参考含 FEA。
- 适合研究无位置传感器升级；需接入观察器并记录注入状态。低负载信息弱，加减速中的速度估计误差仍影响结果；不能把 dSPACE 计算时间照搬到 MCU。

### 2. 高频注入＋神经网络电压补偿：Electronics，2026

Xiang, Zhou & Wang. *Online Parameter Identification for Sensorless PMSM Drives with Inverter Nonlinearity Compensation*. 15(12), 2722. [出版方](https://www.mdpi.com/2079-9292/15/12/2722)；[出版方 XML](https://mdpi-res.com/d_attachment/electronics/electronics-15-02722/article_deploy/electronics-15-02722.xml)。

- 5.2 节、图 12、表 3：STM32F407、表贴式电机、磁粉制动器，10 kHz PWM/采样；辨识 Rs、Ld。
- 高频 d 轴注入与 FFNN 电压误差补偿。300 rpm 编码器实验误差为 4.05%/3.91%；同速无位置传感器实验为 5.65%/5.25%，均按文中名义值比较。
- 对 STM32 接入有参考价值；网络先用本台架采样离线训练。它不是四参数完整方案，也不能把 50 rpm 编码器实验说成低速无位置传感器通过。

### 3. IPMSM 四参数同时辨识：CES TEMS，2025

Wang et al. *Online Simultaneous Identification of Multi-Parameters for Interior PMSMs Under Sensorless Control*. 9(4), 422–433，2025 年 12 月卷期。 [DOI](https://doi.org/10.30941/CESTEMS.2025.00029)；[作者上传原文](https://www.researchgate.net/publication/399393488)。

- 原文 V 节、图 9–17、表 III：400 W IPMSM、dSPACE DS1006、10 kHz 开关，包含 400 r/min 实验及不同 dq 电流工况。
- 交替 d 轴电流和位置偏置注入，辨识 Rs、Ld、Lq、磁链；实验另做逆变器补偿。
- 适合独立 Ld/Lq 的无位置传感器扩展。电感对照含工况相关 FEA；文中局部误差不能直接按表 III 名义电感复算，因此这里不拿几个最优百分数排名。

### 4. ZOH＋双采样＋FFRLS：Sensors，2026

He et al. *Online Multi-Parameter Identification for PMSM Parameter Monitoring Based on a ZOH Model and Dual-Sampling Strategy*. 26(3), 1072. [出版方](https://www.mdpi.com/1424-8220/26/3/1072)；[出版方 XML](https://mdpi-res.com/d_attachment/sensors/sensors-26-01072/article_deploy/sensors-26-01072.xml)。

- 第 4 节、图 9、表 1–6：2.5 kW 电机、TMS320F28377D、17 位编码器、对拖负载；4 kHz PWM。
- ZOH 模型、d 轴注入、双采样和逆变器补偿。2000 r/min、4 N·m 时，Rs/L/磁链误差为 5.47%/−4.05%/−2.46%；参考量通过 LCR 与拖动反电势取得。
- 实现按等电感模型处理，不能据此宣称独立识别 Ld/Lq。需保留两次采样的 PWM 相位；论文的 Euler 对比结果不等于已证明优于本 skill 的积分回归。

### 5. 转矩辅助消除位置误差：IET EPA，2026

Wang, Zhu & Feng. *Online Parameter Identification of SPMSMs Under Sensorless Control Cancelling Influence of Position Error With Torque Measurements*. 20(1), e70185. [出版方全文](https://ietresearch.onlinelibrary.wiley.com/doi/10.1049/elp2.70185)。

- 5.1–5.5 节、图 9、表 1–2：600 W SPMSG 发电台架、dSPACE DS1006、负载机与四力传感器构成的转矩测量装置。
- 利用转矩测量、正负位置偏置和顺序分块 EKF 辨识 Rs、L、磁链；Rs 仍依赖逆变器补偿。
- 属于高仪器要求路线。论文明确限制强凸极/IPMSM 的直接应用，低于额定速度 10% 时观察器可靠性不足；不适合作为无转矩传感器通用板的默认方案。

第 4 篇已出现在首轮调研，本轮补充核实实物平台与条件；其余 4 篇为本轮新增。

## 有前沿价值，但暂不算“已核验实物”

| 论文 | 已核对内容 | 当前缺口 |
|---|---|---|
| *Virtual Active Flux Injection-Based Online Full-Parameter Estimation of IPMSMs Decoupling From Sensorless Control*，IEEE JESTIE 2026，7(3):924–939，[DOI](https://doi.org/10.1109/JESTIE.2026.3684878) | 题录、出版方摘要；虚拟有功磁链注入与辨识/观察器解耦 | 摘要称实验验证，尚未读取可核查的台架章节 |
| *Virtual Small Signal-Based Online Identification of PMSM Drive System for Model Predictive Control*，IEEE TIE 2026，73(2):1750–1759，[作者机构页面](https://nottingham-repository.worktribe.com/output/54928787/virtual-small-signal-based-online-identification-of-pmsm-drive-system-for-model-predictive-control) | 题录和机构摘要；利用 MPC 自带高频信息，无额外物理注入 | 页面声称实验，但台架、误差基准和实现细节尚未核验；也不能直接搬到 PI-FOC |
| *Generalized Unbiased Parameters Identification for PMSM Based on Information Enrichment and Convergence Correction*，IEEE TTE 2026，12(3):5064–5077，[作者机构页面](https://portal.fis.tum.de/de/publications/generalized-unbiased-parameters-identification-for-pmsm-based-on-/) | 题录、机构摘要；信息量筛选和迭代偏差修正 | 尚未读取可核查的实物实验章节 |

IEEE 新论文的 DOI 年份可能早于正式卷期：例如 MPC 那篇 DOI 带 2025，正式卷期为 2026。此处不使用聚合网站默认的“January”日期替代出版记录。

## 对本 skill 的升级建议

以下是结合现有实现作出的工程判断，尚未实现或在本项目电机上复现：

1. **优先补可信电压。** 按具体逆变器准备标定/补偿资料，先比较物理补偿与小型 FFNN，再考虑在线辨识。把训练工况、电流范围、母线电压和温度适用范围记录下来，不能给所有板卡共用一个未经标定的网络。
2. **再匹配数字控制时序。** 具备双采样硬件时研究 ZOH/FFRLS；扩充 PWM/ADC 相位和两次采样记录。当前 PMI1 六量记录不足以表达全部双采样条件。
3. **无位置传感器另设适配层。** 研究虚拟信号或双信号注入前，先暴露观察器、注入状态和电压重建接口。保留现有离线积分算法作同数据基线，检查信息量、工况重复性、执行时间和独立预测。
4. **按物理基准验收。** 电阻对照需说明温度；电感需说明电流、位置、频率及增量/表观定义；磁链对照需说明反电势定义。实物台架存在、参数误差小和通用板卡可复现是三件不同的事。

不建议直接把当前基线换成更大的优化器或神经网络。先复现一篇与实际控制板、反馈类型和可采信号相符的已核验论文，再决定是否升级默认算法。

现已增加 [标准模块 Simulink 验证包](../simulink/README.md)，单独比较第 2 篇启发的“小型 FFNN 电压误差补偿”思路与现有积分回归。它包含独立合成标定、噪声、标定漂移和无激励案例；没有复现原文的高频注入、在线算法或无位置传感器闭环。仿真指标不能与上述实物误差直接排名。
