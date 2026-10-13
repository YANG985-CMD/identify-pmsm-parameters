function [data, meta, truth] = pmsm_simulated_experiment(options)
%PMSM_SIMULATED_EXPERIMENT Independent continuous-time test plant, not a dataset of a real motor.
arguments
    options.ExperimentID {mustBeTextScalar} = "synthetic-train"
    options.Phase (1,1) {mustBeNumeric,mustBeReal,mustBeFinite} = 0
    options.Salient (1,1) logical = true
    options.CurrentNoiseStd (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeNonnegative} = 0
    options.VoltageNoiseStd (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeNonnegative} = 0
end
truth = struct('Rs',0.7,'Ld',0.004,'Lq',0.006,'psi_f',0.03);
if ~options.Salient
    truth.Lq = truth.Ld;
end
t = (0:1e-4:0.3).';
phase = options.Phase;
inputs = @(time) [1.2+0.8*sin(2*pi*31*time+phase)+0.35*sin(2*pi*9*time); ...
    5+1.1*cos(2*pi*17*time+phase)+0.6*sin(2*pi*4*time); ...
    160+40*sin(2*pi*3*time+phase)];
% Integrate the physical differential model, independently of integral regression.
plant = @(time,x) plantDerivative(time,x,inputs,truth);
[~,currents] = ode45(plant,t,[0;0],odeset('RelTol',1e-10,'AbsTol',1e-12));
signals = inputs(t.');
state = rng;
cleanup = onCleanup(@() rng(state));
rng(117,'twister');
currents = currents+options.CurrentNoiseStd*randn(size(currents));
voltages = signals(1:2,:).'+options.VoltageNoiseStd*randn(numel(t),2);
data = table(t,currents(:,1),currents(:,2),voltages(:,1),voltages(:,2),signals(3,:).', ...
    VariableNames={'t','id','iq','ud','uq','omega_e'});
meta = struct('experiment_id',string(options.ExperimentID), ...
    'source_kind',"simulation",'dq_convention',"amplitude_invariant", ...
    'speed_kind',"electrical",'d_axis',"pm_flux",'angle_source',"simulation", ...
    'voltage_source',"simulation",'time_alignment',"verified", ...
    'units',struct('t',"s",'id',"A",'iq',"A",'ud',"V",'uq',"V",'omega_e',"rad/s"));
end

function dx = plantDerivative(time,x,inputs,p)
u = inputs(time);
resistive = p.Rs*x;
crossD = u(3)*p.Lq*x(2);
crossQ = u(3)*(p.Ld*x(1)+p.psi_f);
dx = [(u(1)-resistive(1)+crossD)/p.Ld; ...
    (u(2)-resistive(2)-crossQ)/p.Lq];
end
