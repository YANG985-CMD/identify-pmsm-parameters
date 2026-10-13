function record = pmsm_simulate_mechanical(bench,inputSignals,experimentID,kind,options)
%PMSM_SIMULATE_MECHANICAL Run actual current and mechanical states with Dataset.
arguments
    bench (1,1) struct
    inputSignals table
    experimentID {mustBeTextScalar}
    kind {mustBeMember(kind,["friction_steady","mechanical_dynamic"])} = "mechanical_dynamic"
    options.SpeedNoiseStd (1,1) double {mustBeFinite,mustBeNonnegative} = 0
    options.TorqueNoiseStd (1,1) double {mustBeFinite,mustBeNonnegative} = 0
    options.Seed (1,1) double {mustBeInteger,mustBeNonnegative} = 11
end
names = {'t','omega_reference','iq_injection','id_reference','load_torque'};
if ~all(ismember(names,inputSignals.Properties.VariableNames)) || ...
        any(~isfinite(inputSignals{:,names}),'all') || inputSignals.t(1) ~= 0 || ...
        any(diff(inputSignals.t) <= 0) || inputSignals.t(end) < bench.StopTime
    error('pmsm:MechanicalInputs','Finite inputs must start at zero and cover the simulation interval.');
end
folder = fileparts(mfilename('fullpath')); model = 'pmsm_mechanical_bench';
if ~bdIsLoaded(model), open_system(fullfile(folder,[model,'.slx'])); end
dataset = Simulink.SimulationData.Dataset;
for k = 2:numel(names)
    dataset = dataset.addElement(timeseries(inputSignals.(names{k}),inputSignals.t),names{k});
end
in = Simulink.SimulationInput(model);
in = in.setVariable('bench',bench,'Workspace',model);
in = in.setExternalInput(dataset);
in = in.setModelParameter('StopTime',num2str(bench.StopTime,17),'FixedStep',num2str(bench.SolverStep,17));
out = sim(in);
values = out.yout.getElement(1).Values;
t = (0:bench.SamplePeriod:bench.StopTime).';
indices = interp1(values.Time,(1:numel(values.Time)).',t,'nearest');
if any(abs(values.Time(indices)-t) > bench.SolverStep/2)
    error('pmsm:MechanicalAlignment','Saved telemetry is not aligned with sample times.');
end
signals = values.Data(indices,:);
oldRng = rng; cleanup = onCleanup(@() rng(oldRng)); rng(options.Seed,'twister');
omega_m = signals(:,1)+options.SpeedNoiseStd*randn(size(t));
torque_e = signals(:,2)+options.TorqueNoiseStd*randn(size(t));
load_torque = signals(:,3); id = signals(:,4); iq = signals(:,5); theta_m = signals(:,6);
data = table(t,omega_m,torque_e,load_torque,id,iq,theta_m);
meta = struct('experiment_id',string(experimentID),'configuration_id',"simulink-rigid-shaft", ...
    'source_kind',"simulation",'experiment_type',string(kind),'torque_source',"simulation", ...
    'torque_scale_evidence',"Simulink current states and explicit PMSM torque equation", ...
    'speed_source',"simulation",'shaft_reference',"motor",'inertia_scope',"motor_and_attached_load", ...
    'time_alignment',"verified",'load_model',"measured",'friction_model',"viscous_coulomb_sign", ...
    'units',struct('t',"s",'omega_m',"rad/s",'torque_e',"N*m",'load_torque',"N*m"));
record = struct('data',data,'meta',meta,'bench',bench);
end
