function result = pmsm_identify_mechanical(source,meta,friction,options)
%PMSM_IDENTIFY_MECHANICAL Fit J and optionally one constant load using integrals.
arguments
    source
    meta (1,1) struct
    friction (1,1) struct
    options.WindowSamples (1,1) double {mustBeFinite,mustBeInteger,mustBePositive} = 40
    options.MinSpeedChange (1,1) double {mustBeFinite,mustBePositive} = 0.2
    options.MaxCondition (1,1) double {mustBeFinite,mustBeGreaterThan(options.MaxCondition,1)} = 1e6
end
if ~isfield(friction,'kind') || friction.kind ~= "pmsm_friction" || friction.status ~= "estimated_unvalidated"
    error('pmsm:FrictionCandidate','Provide an identifiable, nonnegative friction estimate.');
end
[data,audit] = pmsm_mechanical_audit(source,meta,MinSpeed=friction.options.MinSpeed);
if string(meta.experiment_type) ~= "mechanical_dynamic"
    error('pmsm:MechanicalConditions','J identification requires a mechanical_dynamic experiment.');
end
if string(meta.inertia_scope) ~= string(friction.metadata.inertia_scope) || string(meta.configuration_id) ~= string(friction.metadata.configuration_id)
    error('pmsm:MechanicalScope','Friction and inertia must use the same declared attachment scope.');
end
if audit.fingerprint == friction.dataFingerprint || string(meta.experiment_id) == string(friction.metadata.experiment_id)
    error('pmsm:MechanicalIndependentData','Friction and dynamic identification must use distinct records and experiment IDs.');
end
constantUnknown = string(meta.load_model) == "constant_unknown";
matrix = zeros(0,1+double(constantUnknown)); y = zeros(0,1); intervals = zeros(0,2); rejected = 0;
for first = 1:options.WindowSamples:height(data)-options.WindowSamples
    last = first+options.WindowSamples; rows = first:last;
    if ~all(audit.validRows(rows)) || any(audit.breakBefore(first+1:last))
        rejected = rejected+1; continue
    end
    duration = data.t(last)-data.t(first);
    change = data.omega_m(last)-data.omega_m(first);
    row = change/duration;
    if constantUnknown, row = [row,1]; end %#ok<AGROW>
    matrix(end+1,:) = row; %#ok<AGROW>
    frictionTorque = friction.parameters.B*data.omega_m(rows)+friction.parameters.Tc*sign(data.omega_m(rows));
    y(end+1,1) = trapz(data.t(rows),data.torque_e(rows)-data.load_torque(rows)-frictionTorque)/duration; %#ok<AGROW>
    intervals(end+1,:) = [first,last]; %#ok<AGROW>
end
% Constant load may have either sign; scale/rank must still be checked.
if constantUnknown
    [theta,diagnostics,status] = pmsm_mechanical_solve(matrix,y,options.MaxCondition,[1,-1]);
else
    [theta,diagnostics,status] = pmsm_mechanical_solve(matrix,y,options.MaxCondition,true);
end
if isempty(intervals) || max(abs(matrix(:,1).*(data.t(intervals(:,2))-data.t(intervals(:,1))))) < options.MinSpeedChange
    status = "not_identifiable"; theta(:) = NaN;
end
diagnostics.usedWindows = size(matrix,1); diagnostics.rejectedWindows = rejected;
parameters = struct('J',theta(1),'B',friction.parameters.B,'Tc',friction.parameters.Tc,'trainingLoadTorque',NaN);
if constantUnknown, parameters.trainingLoadTorque = theta(2); end
result = struct('schemaVersion',"1.0",'kind',"pmsm_mechanical",'algorithm',"staged_integral_scaled_ls", ...
    'status',status,'parameters',parameters,'metadata',meta,'audit',audit,'friction',friction, ...
    'options',options,'dataFingerprint',audit.fingerprint,'diagnostics',diagnostics,'usedIntervals',intervals, ...
    'limitations',["J is the declared rotor or combined inertia referred to the motor shaft. Friction is held from a separate steady experiment, not refitted here."; ...
    "An arbitrary unknown time-varying load is not identifiable with J/B from these signals. Torque-scale error propagates to J/B/Tc; independent speed prediction does not prove absolute parameter accuracy."]);
end
