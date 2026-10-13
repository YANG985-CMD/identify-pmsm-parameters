function validation = pmsm_validate_mechanical(result,source,meta,options)
%PMSM_VALIDATE_MECHANICAL Predict speed on a third known-load experiment.
arguments
    result (1,1) struct
    source
    meta (1,1) struct
    options.MaxRMSE (1,1) double {mustBeNonnegative} = Inf
end
if ~isfield(result,'kind') || result.kind ~= "pmsm_mechanical" || result.status ~= "estimated_unvalidated"
    error('pmsm:MechanicalCandidate','Provide an identifiable physical mechanical candidate.');
end
[data,audit] = pmsm_mechanical_audit(source,meta,MinSpeed=result.friction.options.MinSpeed);
if string(meta.load_model) == "constant_unknown"
    error('pmsm:MechanicalValidationLoad','Independent prediction needs known zero or measured load; do not assume the training load persists.');
end
if string(meta.inertia_scope) ~= string(result.metadata.inertia_scope) || string(meta.configuration_id) ~= string(result.metadata.configuration_id)
    error('pmsm:MechanicalScope','Independent experiment must use the same attachment scope.');
end
if audit.fingerprint == result.dataFingerprint || audit.fingerprint == result.friction.dataFingerprint || ...
        string(meta.experiment_id) == string(result.metadata.experiment_id) || string(meta.experiment_id) == string(result.friction.metadata.experiment_id)
    error('pmsm:MechanicalIndependentData','Validation must be distinct from friction and J fitting records.');
end
prediction = nan(height(data),1); p = result.parameters;
for run = unique(audit.runId(audit.validRows)).'
    rows = find(audit.validRows & audit.runId == run);
    if numel(rows) < 3, continue; end
    t = data.t(rows); signValue = sign(data.omega_m(rows(1)));
    netTorque = data.torque_e(rows)-data.load_torque(rows)-p.Tc*signValue;
    [~,speed] = ode45(@(time,w) (interp1(t,netTorque,time,'linear')-p.B*w)/p.J, ...
        t,data.omega_m(rows(1)),odeset('RelTol',1e-7,'AbsTol',1e-8));
    prediction(rows(2:end)) = speed(2:end);
end
scored = audit.validRows & isfinite(prediction);
if ~any(scored), error('pmsm:MechanicalNoValidation','No dynamic prediction runs with at least three usable samples.'); end
rmse = sqrt(mean((prediction(scored)-data.omega_m(scored)).^2));
status = "metrics_only";
if isfinite(options.MaxRMSE)
    status = "prediction_check_failed";
    if rmse <= options.MaxRMSE, status = "prediction_check_passed"; end
end
validation = struct('schemaVersion',"1.0",'status',status,'rmseRadPerSecond',rmse, ...
    'maxRMSE',options.MaxRMSE,'scoredSamples',sum(scored),'t',data.t, ...
    'measuredSpeed',data.omega_m,'predictedSpeed',prediction,'metadata',meta,'audit',audit, ...
    'trainingFingerprint',result.dataFingerprint,'frictionFingerprint',result.friction.dataFingerprint, ...
    'dataFingerprint',audit.fingerprint,'limitations',"Prediction uses electromagnetic torque and known load. Only run-start measured speed initializes states; zero-speed crossings and gaps reset runs. Electrical-model torque shares current and parameter uncertainties.");
end
