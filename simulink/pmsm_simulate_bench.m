function record = pmsm_simulate_bench(bench, experimentID, options)
%PMSM_SIMULATE_BENCH Run the actual Simulink diagram and retain command/actual voltages.
arguments
    bench (1,1) struct
    experimentID {mustBeTextScalar}
    options.CurrentNoiseStd (1,1) double {mustBeNonnegative,mustBeFinite} = 0
    options.VoltageNoiseStd (1,1) double {mustBeNonnegative,mustBeFinite} = 0
    options.Seed (1,1) double {mustBeInteger,mustBeNonnegative} = 117
end
model = 'pmsm_id_bench';
if ~bdIsLoaded(model)
    open_system(fullfile(fileparts(mfilename('fullpath')),[model,'.slx']));
end
in = Simulink.SimulationInput(model);
in = in.setVariable('bench',bench,Workspace=model);
in = in.setModelParameter('StopTime',num2str(bench.StopTime,17), ...
    'FixedStep',num2str(bench.SolverStep,17));
out = sim(in);
values = out.yout.getElement(1).Values;
expectedTime = (0:bench.SamplePeriod:bench.StopTime).';
rows = zeros(numel(expectedTime),1);
for k = 1:numel(expectedTime)
    [distance,rows(k)] = min(abs(values.Time-expectedTime(k)));
    if distance > bench.SolverStep/2
        error('pmsm:BenchSampling','Expected synchronized telemetry timestamp is missing.');
    end
end
t = values.Time(rows);
signals = reshape(values.Data(rows,:),numel(rows),8);
data = table(t,signals(:,1),signals(:,2),signals(:,3),signals(:,4),signals(:,7), ...
    signals(:,8),signals(:,5),signals(:,6), ...
    VariableNames={'t','id','iq','ud','uq','omega_e','theta_e','ud_actual','uq_actual'});
oldRng = rng;
cleanup = onCleanup(@() rng(oldRng));
rng(options.Seed,'twister');
data.id = data.id+options.CurrentNoiseStd*randn(height(data),1);
data.iq = data.iq+options.CurrentNoiseStd*randn(height(data),1);
data.ud = data.ud+options.VoltageNoiseStd*randn(height(data),1);
data.uq = data.uq+options.VoltageNoiseStd*randn(height(data),1);
meta = struct('experiment_id',string(experimentID),'source_kind',"simulation", ...
    'dq_convention',"amplitude_invariant",'speed_kind',"electrical",'d_axis',"pm_flux", ...
    'angle_source',"simulation",'voltage_source',"simulation",'time_alignment',"verified", ...
    'voltage_input_kind',"command", ...
    'units',struct('t',"s",'id',"A",'iq',"A",'ud',"V",'uq',"V",'omega_e',"rad/s"), ...
    'simulation',struct('model',model,'bench',bench,'sensorNoise',options));
record = struct('data',data,'meta',meta,'truth', ...
    struct('Rs',bench.Rs,'Ld',bench.Ld,'Lq',bench.Lq,'psi_f',bench.Flux));
end
