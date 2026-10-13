function record = pmsm_compensate_record(record, network)
%PMSM_COMPENSATE_RECORD Reconstruct dq voltage from independent phase calibration.
arguments
    record (1,1) struct
    network (1,1) struct
end
if ~isfield(record.meta,'source_kind') || string(record.meta.source_kind) ~= "simulation"
    error('pmsm:BenchOnly','This helper is a synthetic-benchmark example; physical compensation needs verified device calibration.');
end
if ~isfield(record.meta,'voltage_input_kind') || string(record.meta.voltage_input_kind) ~= "command"
    error('pmsm:VoltageInputKind','Compensation requires the original command voltage; do not compensate twice.');
end
data = record.data;
theta = data.theta_e;
angle = theta+[0,-2*pi/3,2*pi/3];
phaseCurrent = data.id.*cos(angle)-data.iq.*sin(angle);
phaseError = pmsm_predict_voltage_error(network,phaseCurrent);
alpha = (2*phaseError(:,1)-phaseError(:,2)-phaseError(:,3))/3;
beta = (phaseError(:,2)-phaseError(:,3))/sqrt(3);
data.ud = data.ud-alpha.*cos(theta)-beta.*sin(theta);
data.uq = data.uq+alpha.*sin(theta)-beta.*cos(theta);
record.data = data;
record.meta.voltage_input_kind = "independent_ffnn_compensation";
record.meta.compensation = struct('method',network.method, ...
    'calibrationCurrentRangeAmps',network.currentRangeAmps, ...
    'calibrationRMSEVolts',network.calibrationRMSEVolts, ...
    'calibrationSource',"separate_synthetic_phase_voltage_measurements");
end
