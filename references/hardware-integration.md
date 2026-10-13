# 通用实机数据接入

## 通用的范围

通用的是 PMSM/适用 FOC 无刷电机的 SI dq 数据约定、板端记录格式、上位机接收和 MATLAB 辨识验证。板端编码器不依赖某个 HAL；它要求 C99、8 位字节、32 位 IEEE-754 float、uint32_t/uint64_t，不满足时编译拒绝。其他字节宽度的平台需要另写线格式适配，不能直接复制此 C 编码器。当前只有主机编译与软件链路验证，没有为 STM32、ESP32 等板卡分别完成物理验收。

板卡仍需适配 ADC 标定、角度与相序、信号缩放、时序、电压重建和传输。霍尔插值或无位置传感器信号会带来额外模型误差；无位置传感器观察器如果依赖待估参数，还要审查循环依赖。异步电机、直流电机、六步换相原始相量不能直接套用当前 dq 内核。

```mermaid
flowchart LR
    A[控制板同步采样] --> B[板卡适配：单位、坐标、时间]
    B --> C[PMI1 记录：缓冲后传输]
    C --> D[串口接收或文件回放]
    D --> E[CSV、元数据、原始记录和校验摘要]
    E --> F[MATLAB 可辨识性与参数估计]
    F --> G[另一实验的电流预测与结果导出]
```

## 每块板需提供什么

| 适配项 | 必须提供的实际含义 |
|---|---|
| 时间 | 采样时的单调 uint64 微秒时钟；32 位计时器需可靠扩展，不能用发送时间 |
| id / iq | 实际电流，A，幅值不变 dq；不是电流指令 |
| ud / uq | 对应采样区间的平均电压，V；说明实测、补偿重建或指令来源 |
| omega_e | 有符号电角速度 rad/s；机械 rpm 先使用可信极对数换算 |
| 状态 | valid=0 标出不可用采样；saturated=1 标出削顶/饱和 |
| 序号与实验 | sequence 每个约定记录时刻递增，丢记录也递增；run_id 在重启或重新采集时改变 |

在控制中断中保存一致快照，完整记录通过双缓冲、短临界区或平台已验证机制交给后台。这里的 C 文件只负责编码，不提供缓冲同步。不得在高频控制中断内阻塞发串口，也不能把 volatile 当成多字段原子快照。

使用当前控制周期还是前一周期平均电压要依据 PWM/ADC 时序确定，不能简单抓取同一次循环的 PI 输出后声称同步。电角零点、功率不变 dq、标幺值、峰值/RMS、线量/相量均须显式处理。`meta.time_alignment="verified"` 需要外部证据，程序不会替你证明。

`firmware/pmsm_capture.h/.c` 的入口为 `pmsm_capture_pack(buffer, capacity, &sample)`；输出固定 48 字节。在后台从稳定的快照缓冲区编码，再交给本板的 UART/USB/SD 等发送函数。CAN 需要板端分片及主机重组适配，当前没有内置 CAN 接收驱动。

## PMI1 线格式

均为 little-endian，帧长 48 字节；禁止直接发送 C 结构体内存，避免填充和大小端问题。

| 偏移 | 字段 | 格式 |
|---|---|---|
| 0 | magic | ASCII PMI1，4 字节 |
| 4 | version | uint8，1 |
| 5 | flags | uint8，bit0 valid，bit1 saturated，其余必须为 0 |
| 6 | length | uint16，48 |
| 8 | sequence | uint32，可从 0xffffffff 回绕到 0 |
| 12 | run_id | uint32，单次采集内固定 |
| 16 | timestamp_us | uint64，采样时间 |
| 24 / 28 | id / iq | IEEE-754 float32，A |
| 32 / 36 | ud / uq | IEEE-754 float32，V |
| 40 | omega_e | IEEE-754 float32，rad/s |
| 44 | CRC-32 | uint32，对字节 0..43，反射多项式 0xedb88320，初值与末异或均 0xffffffff；与 Python zlib.crc32 一致 |

坏帧、乱码和丢序号会形成 `segment` 边界。无效行和饱和行保留，由 MATLAB 排除；不插值跨越它们。重复/倒序、时钟回退、run_id 改变直接拒绝整次采集进入自动辨识，原始文件及失败摘要保留。

采样率不能由一个“通用值”确定，应覆盖电气动态和激励频带，并通过更高采样率或积分窗口敏感性验证。48 字节/样本、UART 8N1 理想情况下约需 `480 × 采样率` bit/s：10 kHz 连续传输需要至少 4.8 Mbaud，尚未计入余量；115200 baud 理论上只有 240 样本/s。优先考虑板端短时高速缓存后慢速导出、USB 或经过验证的高速传输，不能用降采样后速度曲线代替电气动态数据。

## 从记录到参数

1. 复制 [hardware-meta.example.json](../assets/hardware-meta.example.json)，填实际来源和唯一实验 ID。示例故意保留未知项，未填写的角度/电压来源会被拒绝。硬件证据字段用于追溯，未知时保持 null，不伪造。
2. 已有 PMI1 原始二进制文件可离线解码，只需 Python 3.10+ 标准库：

```sh
python -B scripts/pmsm_capture.py decode --input run001.bin --meta run001-meta.json --output-dir captures/run001
```

3. 需要实时串口接收时安装 pySerial，并根据板卡实际接线选择 DTR/RTS 电平：

```sh
python -B scripts/pmsm_capture.py serial --port COM3 --baud 1000000 --seconds 10 --dtr 0 --rts 0 --meta run001-meta.json --output-dir captures/run001
```

这只是调用形式，端口、波特率、时长及控制线电平必须与实际板卡一致。接收器不发送任何电机命令；但打开端口时操作系统/USB 驱动可能瞬时改变 DTR/RTS 并复位板子。先确认端口打开的物理影响和本次采集授权，串口只能由一个程序占用。[pySerial 官方 API](https://pyserial.readthedocs.io/en/latest/pyserial_api.html)

每次输出新目录：`raw.bin`、`samples.csv`、`meta.json`、`capture.json`；已有目录拒绝覆盖。接收有时长与字节上限，异常时保留部分数据并标为 capture_failed。程序退出只结束接收，不会停止电机；实验的停止动作和保护由原控制器负责。

4. 用另一次独立实验生成第二个采集目录，在 MATLAB 添加 scripts 路径后运行：

```matlab
[estimate,validation] = pmsm_identify_capture( ...
    'captures/run001','captures/run002','results/candidate001', ...
    Model="ipmsm",WindowSamples=20);
```

入口核对三个输入文件的 SHA-256、拒绝失败采集，随后使用原有可辨识性检查、跨实验验证和导出。不指定 MaxRMSE 时只报告指标；哈希检查发现文件改动，不证明硬件校准或实验独立性，摘要也不是防篡改签名。

现有板卡如果已导出正确 SI dq CSV，可直接用原 MATLAB 接口，无需改成 PMI1。这里没有自动判断未知协议、自动转换未知缩放或自动补齐缺失电压。

## 辨识实验的安排

先核对采样与物理量，再根据可辨识性安排静止电阻/电感试验以及有转速的磁链试验，最后用另一组工况验证。静止数据没有磁链信息；不能把同一恒速 id=0 数据自然视为四参数充分激励。试验电流、电压、转速、持续时间、转子约束和停机方式来自具体电机与功率板的依据。

MathWorks 的测量参数化示例也把锁转子 R/L、固定转速反电势和机械参数试验分开设计；该示例本身使用已知参数的模拟测试，不能作为本项目的实机验证。[官方示例](https://www.mathworks.com/help/simscape-electrical/ug/parameterize-a-pmsm-from-measurements.html)

当前通用接入层不生成测试电流、不启动或停机、不下发参数、不刷写固件。未来自动实验仍需板级执行接口与已经验证的限幅、停机及硬件保护，不能通过一份通用 JSON 证明设备允许通电。
