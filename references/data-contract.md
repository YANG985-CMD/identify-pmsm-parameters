# 输入数据与元数据

接受 MATLAB table、CSV 路径或包含 `data` table 的 MAT 文件。原始文件只读。timetable、Simulink Dataset、原始 abc 及串口帧须显式转换为 table，保存转换记录。

| 字段 | 单位 | 含义 |
|---|---|---|
| t | s | 严格递增的真实采样时间戳 |
| id, iq | A | 实际电流、幅值不变 dq |
| ud, uq | V | 同一坐标系与时刻的电压，来源另行声明 |
| omega_e | rad/s | 有符号电角速度 |
| valid（可选） | 0/1 | false 样本及跨越它的窗口排除 |
| saturated（可选） | 0/1 | true 标记不应使用的削顶/饱和样本 |
| segment（可选） | 有限数值 | 相邻标签改变时建立积分/预测边界 |

所有字段为实数数值列。除时间外非有限值可保留但作为无效样本；时间非有限、重复、倒序直接报错。不删除无效行后拼接，否则产生伪动态。相邻时间间隔大于中位数 1.5 倍视为间断，这是启发式，不能证明没有丢帧。不同采样率实验分开处理，不依赖单一全局中位数。

## 元数据格式

以下只是声明格式，不能替代硬件校准：

```matlab
meta = struct( ...
    'experiment_id',"motorA-run001", ...
    'source_kind',"measurement", ...
    'dq_convention',"amplitude_invariant", ...
    'speed_kind',"electrical", ...
    'd_axis',"pm_flux", ...
    'angle_source',"encoder", ...
    'voltage_source',"measured", ...
    'time_alignment',"verified", ...
    'units',struct('t',"s",'id',"A",'iq',"A", ...
                   'ud',"V",'uq',"V",'omega_e',"rad/s"));
```

允许值：

- source_kind: measurement / simulation。
- angle_source: encoder / hall_interpolated / sensorless / simulation。
- voltage_source: measured / reconstructed_compensated / command / simulation。
- time_alignment: verified / unverified。

真实测量不能声明仿真电压/角度。重建补偿电压必须有占空比、母线电压、死区/压降补偿及变换依据。`metadataMeetsPreferredConditions` 只是标签检查，不是校准证书。程序不能识别被错误标注为 rad/s 的 rpm 数值。

额外建议保存：极对数、接线方式、电机类型依据、型号、额定值、PWM 周期、ADC 采样点、日志抽取率、滤波延迟、温度、负载、位置零偏与相序。附加 meta 字段原样保留。

机械速度换算为 `omega_e = polePairs * rpm * 2*pi/60`，先核对极对数。缺少相序/电角零点依据时不从 abc 猜 dq。功率不变 dq、RMS 相量、标幺量须显式数值转换，不能只改标签。

## 独立性与输出

训练和验证须不同 experiment_id 和不同原始记录。SHA-256 对六个必需数值列生成指纹，阻止同一数据改名复用，忽略文件名和附加列。指纹不能证明无重叠或无泄漏，仍需审查实验来源。

导出文件：estimate.mat（完整候选与验证）、parameters.csv（数值、单位、来源）、summary.json（诊断和限制）、validation_currents.csv（实测/预测电流）。同名文件拒绝覆盖。JSON 的 NaN/Inf 编码为 null，须结合状态；MAT 保留非有限数值。psi_f 是当前 dq 定义的永磁相磁链，不直接等于任意单位的 Ke。
