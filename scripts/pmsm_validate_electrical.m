function validation = pmsm_validate_electrical(result, source, meta, options)
%PMSM_VALIDATE_ELECTRICAL Predict independent current records from measured inputs.
% Resets only at invalid samples, gaps, or explicit experiment boundaries.
arguments
    result (1,1) struct
    source
    meta (1,1) struct
    options.MaxRMSE (1,2) {mustBeNumeric,mustBeReal,mustBePositive} = [Inf,Inf]
end
if ~isfield(result,'status') || result.status ~= "estimated_unvalidated"
    error('pmsm:EstimateNotUsable', 'Validation requires a finite physical identified candidate.');
end
[data,audit] = pmsm_audit(source,meta);
if audit.fingerprint == result.dataFingerprint || ...
        string(meta.experiment_id) == string(result.metadata.experiment_id)
    error('pmsm:ValidationLeakage', 'Use a separate experiment ID and a different held-out record.');
end
p = result.parameters;
prediction = nan(height(data),2);
runIds = unique(audit.runId(audit.validRows));
runCount = 0;
for k = 1:numel(runIds)
    rows = find(audit.validRows & audit.runId == runIds(k));
    if numel(rows) < 3
        continue
    end
    t = data.t(rows);
    input = griddedInterpolant(t,[data.ud(rows),data.uq(rows),data.omega_e(rows)],'linear','nearest');
    rhs = @(time,current) derivative(time,current,input,p);
    [~,current] = ode45(rhs,t,[data.id(rows(1));data.iq(rows(1))], ...
        odeset('RelTol',1e-7,'AbsTol',1e-9,'MaxStep',max(diff(t))));
    prediction(rows,:) = current;
    % The measured seed is not an independent prediction; exclude it from metrics.
    prediction(rows(1),:) = NaN;
    runCount = runCount+1;
end
scored = all(isfinite(prediction),2);
if ~any(scored)
    error('pmsm:NoValidationData','No continuous validation run with at least three usable samples.');
end
measured = [data.id,data.iq];
errorValue = measured(scored,:)-prediction(scored,:);
rmse = sqrt(mean(errorValue.^2,1));
amplitude = std(measured(scored,:),0,1);
nrmse = rmse./amplitude;
nrmse(amplitude == 0) = NaN;
status = "metrics_only";
if all(isfinite(options.MaxRMSE))
    if all(rmse <= options.MaxRMSE)
        status = "prediction_check_passed";
    else
        status = "prediction_check_failed";
    end
end
validation = struct('schemaVersion',"1.0",'status',status,'rmseAmps',rmse, ...
    'normalizedRMSE',nrmse,'maxRMSEAmps',options.MaxRMSE,'scoredSamples',sum(scored), ...
    'continuousRuns',runCount,'audit',audit,'metadata',meta, ...
    'trainingFingerprint',result.dataFingerprint,'dataFingerprint',audit.fingerprint, ...
    't',data.t,'measuredCurrents',measured,'predictedCurrents',prediction, ...
    'limitations',"Separate experiment IDs are caller declarations. Current prediction agreement is not a parameter truth-error measurement. Inputs are linearly interpolated; verify this matches logging semantics.");
end

function dx = derivative(time,current,input,p)
u = input(time);
dx = [(u(1)-p.Rs*current(1)+u(3)*p.Lq*current(2))/p.Ld; ...
    (u(2)-p.Rs*current(2)-u(3)*(p.Ld*current(1)+p.psi_f))/p.Lq];
end
