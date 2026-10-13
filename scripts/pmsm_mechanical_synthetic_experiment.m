function [data,meta,truth] = pmsm_mechanical_synthetic_experiment(kind,options)
%PMSM_MECHANICAL_SYNTHETIC_EXPERIMENT Known synthetic mechanics for regression.
arguments
    kind {mustBeMember(kind,["friction_steady","mechanical_dynamic"])} = "mechanical_dynamic"
    options.ExperimentID {mustBeTextScalar} = "synthetic-mechanical"
    options.Phase (1,1) double {mustBeFinite} = 0
    options.LoadTorque (1,1) double {mustBeFinite} = 0
    options.SpeedNoiseStd (1,1) double {mustBeFinite,mustBeNonnegative} = 0
    options.TorqueNoiseStd (1,1) double {mustBeFinite,mustBeNonnegative} = 0
    options.Seed (1,1) double {mustBeInteger,mustBeNonnegative} = 51
end
truth = struct('J',0.002,'B',0.001,'Tc',0.02);
meta = struct('experiment_id',string(options.ExperimentID),'configuration_id',"synthetic-rigid-shaft", ...
    'source_kind',"simulation",'experiment_type',string(kind),'torque_source',"simulation", ...
    'torque_scale_evidence',"Independent differential mechanical plant with explicit synthetic constants", ...
    'speed_source',"simulation",'shaft_reference',"motor",'inertia_scope',"motor_and_attached_load", ...
    'time_alignment',"verified",'load_model',"measured",'friction_model',"viscous_coulomb_sign", ...
    'units',struct('t',"s",'omega_m',"rad/s",'torque_e',"N*m",'load_torque',"N*m"));
oldRng = rng; cleanup = onCleanup(@() rng(oldRng)); rng(options.Seed,'twister');
if string(kind) == "friction_steady"
    t = (0:0.001:2.399).'; segment = floor(t/0.4)+1;
    speeds = [-80,-45,-20,20,45,80]; omega_m = reshape(speeds(segment),[],1);
    torque_e = truth.B*omega_m+truth.Tc*sign(omega_m)+options.LoadTorque;
else
    t = (0:0.001:2).';
    torque_e = torque(t,options.Phase,options.LoadTorque);
    [~,omega_m] = ode45(@(time,w) (torque(time,options.Phase,options.LoadTorque)-options.LoadTorque- ...
        truth.B*w-truth.Tc*sign(w))/truth.J,t,35,odeset('RelTol',1e-9,'AbsTol',1e-10,'MaxStep',0.001));
    segment = ones(size(t));
end
omega_m = omega_m+options.SpeedNoiseStd*randn(size(omega_m));
torque_e = torque_e+options.TorqueNoiseStd*randn(size(torque_e));
load_torque = options.LoadTorque*ones(size(t));
data = table(t,omega_m,torque_e,load_torque,segment);
end
function value = torque(t,phase,load)
value = 0.065+load+0.045*sin(2*pi*1.1*t+phase)+0.015*sin(2*pi*3.3*t+phase);
end
