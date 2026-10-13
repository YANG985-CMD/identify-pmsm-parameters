function result = pmsm_identify_friction(source,meta,options)
%PMSM_IDENTIFY_FRICTION Fit B and Coulomb torque from known-load steady runs.
arguments
    source
    meta (1,1) struct
    options.MinSpeed (1,1) double {mustBeFinite,mustBePositive} = 2
    options.MinRunDuration (1,1) double {mustBeFinite,mustBePositive} = 0.15
    options.MaxSteadyAcceleration (1,1) double {mustBeFinite,mustBeNonnegative} = 0.2
    options.MaxSpeedSpan (1,1) double {mustBeFinite,mustBePositive} = 0.5
    options.MaxCondition (1,1) double {mustBeFinite,mustBeGreaterThan(options.MaxCondition,1)} = 1e6
end
[data,audit] = pmsm_mechanical_audit(source,meta,MinSpeed=options.MinSpeed);
if string(meta.experiment_type) ~= "friction_steady" || string(meta.load_model) == "constant_unknown"
    error('pmsm:FrictionConditions','Friction needs steady runs and known zero or measured electromagnetic-opposing load.');
end
matrix = zeros(0,2); y = zeros(0,1); used = zeros(0,2); rejected = 0;
for run = unique(audit.runId(audit.validRows)).'
    rows = find(audit.validRows & audit.runId == run);
    duration = data.t(rows(end))-data.t(rows(1));
    if numel(rows) < 3 || duration < options.MinRunDuration
        rejected = rejected+1; continue
    end
    trend = [data.t(rows)-mean(data.t(rows)),ones(numel(rows),1)]\data.omega_m(rows);
    if abs(trend(1)) > options.MaxSteadyAcceleration || range(data.omega_m(rows)) > options.MaxSpeedSpan
        rejected = rejected+1; continue
    end
    meanSpeed = trapz(data.t(rows),data.omega_m(rows))/duration;
    matrix(end+1,:) = [meanSpeed,sign(meanSpeed)]; %#ok<AGROW>
    y(end+1,1) = trapz(data.t(rows),data.torque_e(rows)-data.load_torque(rows))/duration; %#ok<AGROW>
    used(end+1,:) = [rows(1),rows(end)]; %#ok<AGROW>
end
[theta,diagnostics,status] = pmsm_mechanical_solve(matrix,y,options.MaxCondition,[false,false]);
diagnostics.usedRuns = size(matrix,1); diagnostics.rejectedRuns = rejected;
result = struct('schemaVersion',"1.0",'kind',"pmsm_friction",'algorithm',"steady_run_scaled_ls", ...
    'status',status,'parameters',struct('B',theta(1),'Tc',theta(2)), ...
    'parameterNames',["B","Tc"],'parameterVector',theta,'metadata',meta,'audit',audit, ...
    'options',options,'dataFingerprint',audit.fingerprint,'diagnostics',diagnostics, ...
    'usedIntervals',used,'limitations',"Known load required. B and Tc apply to the declared shaft, speed range and attachment configuration. Near-zero stiction, Stribeck friction and asymmetry are not fitted.");
end
