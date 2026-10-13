function network = pmsm_fit_voltage_network(currentAmps, voltageErrorVolts, options)
%PMSM_FIT_VOLTAGE_NETWORK Five tanh units, calibrated independently of motor fitting.
% Calibration labels must be measured or explicitly synthetic voltage errors.
arguments
    currentAmps (:,1) double {mustBeReal,mustBeFinite}
    voltageErrorVolts (:,1) double {mustBeReal,mustBeFinite}
    options.Iterations (1,1) double {mustBeInteger,mustBePositive} = 8000
    options.Seed (1,1) double {mustBeInteger,mustBeNonnegative} = 41
end
if numel(currentAmps) ~= numel(voltageErrorVolts) || numel(currentAmps) < 15 || ...
        min(currentAmps) >= 0 || max(currentAmps) <= 0
    error('pmsm:VoltageCalibration','Need paired calibration points covering both current signs.');
end
oldRng = rng;
cleanup = onCleanup(@() rng(oldRng));
rng(options.Seed,'twister');
inputScale = max(1,median(abs(currentAmps)));
outputScale = max(abs(voltageErrorVolts));
if outputScale <= eps
    error('pmsm:VoltageCalibration','Calibration voltage error has no usable amplitude.');
end
x = currentAmps.'/inputScale;
target = voltageErrorVolts.'/outputScale;
bestLoss = Inf;
for restart = 1:3
    parameters = [randn(5,1);zeros(5,1);0.2*randn(5,1);0];
    moment = zeros(size(parameters));
    variance = zeros(size(parameters));
    for iteration = 1:options.Iterations
        hidden = tanh(parameters(1:5)*x+parameters(6:10));
        prediction = parameters(11:15).'*hidden+parameters(16);
        delta = 2*(prediction-target)/numel(target);
        hiddenDelta = (parameters(11:15)*delta).*(1-hidden.^2);
        gradient = [hiddenDelta*x.';sum(hiddenDelta,2);hidden*delta.';sum(delta)];
        moment = 0.9*moment+0.1*gradient;
        variance = 0.999*variance+0.001*gradient.^2;
        correction = (moment/(1-0.9^iteration))./(sqrt(variance/(1-0.999^iteration))+1e-8);
        parameters = parameters-0.02*correction;
    end
    hidden = tanh(parameters(1:5)*x+parameters(6:10));
    loss = mean((parameters(11:15).'*hidden+parameters(16)-target).^2);
    if loss < bestLoss
        bestLoss = loss;
        bestParameters = parameters;
    end
end
network = struct('schemaVersion',"1.0",'method',"five_tanh_ffnn_adam", ...
    'weightsInput',bestParameters(1:5),'biasHidden',bestParameters(6:10), ...
    'weightsOutput',bestParameters(11:15).','biasOutput',bestParameters(16), ...
    'inputScale',inputScale,'outputScale',outputScale, ...
    'currentRangeAmps',[min(currentAmps),max(currentAmps)], ...
    'calibrationRMSEVolts',sqrt(bestLoss)*outputScale, ...
    'calibrationCurrentAmps',currentAmps,'calibrationVoltageErrorVolts',voltageErrorVolts, ...
    'iterations',options.Iterations,'seed',options.Seed, ...
    'limitations',"One symmetric inverter phase curve; calibration must match bus voltage, temperature and device. No automatic physical calibration or extrapolation approval.");
end
