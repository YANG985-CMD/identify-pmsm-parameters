function [data,audit] = pmsm_mechanical_audit(source,meta,options)
%PMSM_MECHANICAL_AUDIT Check torque scale, load assumptions and usable runs.
arguments
    source
    meta (1,1) struct
    options.MinSpeed (1,1) double {mustBeFinite,mustBePositive} = 2
    options.GapFactor (1,1) double {mustBeFinite,mustBeGreaterThan(options.GapFactor,1)} = 3
end
data = pmsm_load_data(source);
choice(meta,'source_kind',["measurement","simulation"]);
choice(meta,'experiment_type',["friction_steady","mechanical_dynamic"]);
choice(meta,'torque_source',["calibrated_electromagnetic","dq_model","simulation"]);
choice(meta,'speed_source',["encoder","hall_interpolated","sensorless","simulation"]);
choice(meta,'time_alignment',"verified");
choice(meta,'shaft_reference',"motor");
choice(meta,'inertia_scope',["rotor_only","motor_and_attached_load"]);
choice(meta,'load_model',["known_zero","measured","constant_unknown"]);
choice(meta,'friction_model',"viscous_coulomb_sign");
if ~isfield(meta,'experiment_id') || ~isText(meta.experiment_id) || strlength(string(meta.experiment_id)) == 0
    error('pmsm:MechanicalMetadata','Provide a nonempty experiment_id.');
end
if ~isfield(meta,'configuration_id') || ~isText(meta.configuration_id) || strlength(string(meta.configuration_id)) == 0
    error('pmsm:MechanicalMetadata','State the same motor, attachment and gear configuration_id across all stages.');
end
if ~isfield(meta,'torque_scale_evidence') || ~isText(meta.torque_scale_evidence) || strlength(string(meta.torque_scale_evidence)) == 0
    error('pmsm:MechanicalTorqueScale','State the calibrated electromagnetic torque scale or dq parameter evidence.');
end
if string(meta.source_kind) == "measurement" && ...
        (string(meta.torque_source) == "simulation" || string(meta.speed_source) == "simulation")
    error('pmsm:MechanicalMetadata','Measurement cannot use a simulated torque or speed source.');
end
names = {'t','omega_m','torque_e'}; units = {'s','rad/s','N*m'};
if string(meta.load_model) == "measured"
    names{end+1} = 'load_torque'; units{end+1} = 'N*m';
end
for k = 1:numel(names)
    name = names{k};
    if ~ismember(name,data.Properties.VariableNames)
        error('pmsm:MechanicalMissingSignal','Missing required signal %s.',name);
    end
    if ~isnumeric(data.(name)) || ~isreal(data.(name)) || ~iscolumn(data.(name))
        error('pmsm:MechanicalSignalType','%s must be a real numeric column.',name);
    end
    if ~isfield(meta,'units') || ~isstruct(meta.units) || ~isfield(meta.units,name) || ...
            ~isequal(string(meta.units.(name)),string(units{k}))
        error('pmsm:MechanicalUnits','Explicitly convert %s to %s.',name,units{k});
    end
    data.(name) = double(data.(name));
end
if string(meta.load_model) ~= "measured"
    if ismember('load_torque',data.Properties.VariableNames)
        error('pmsm:MechanicalLoad','Remove unused load_torque or select measured; do not silently ignore a load column.');
    end
    data.load_torque = zeros(height(data),1);
end
if height(data) < 3 || any(~isfinite(data.t)) || any(diff(data.t) <= 0)
    error('pmsm:MechanicalTime','Need at least three finite, strictly increasing timestamps.');
end
valid = all(isfinite(data{:,names}),2) & abs(data.omega_m) >= options.MinSpeed;
for entry = {'valid','saturated'}
    name = entry{1};
    if ismember(name,data.Properties.VariableNames)
        flag = data.(name);
        if (~isnumeric(flag) && ~islogical(flag)) || ~isreal(flag) || ~iscolumn(flag) || any(~ismember(flag,[0,1]))
            error('pmsm:MechanicalFlag','%s must be a 0/1 column.',name);
        end
        if strcmp(name,'valid'), valid = valid & logical(flag); else, valid = valid & ~logical(flag); end
    end
end
segment = ones(height(data),1);
if ismember('segment',data.Properties.VariableNames)
    segment = data.segment;
    if ~isnumeric(segment) || ~isreal(segment) || ~iscolumn(segment) || any(~isfinite(segment)) || any(segment ~= fix(segment))
        error('pmsm:MechanicalSegment','segment must be a finite integer column.');
    end
end
dt = diff(data.t); gap = dt > options.GapFactor*median(dt);
breakBefore = [true;gap | diff(segment) ~= 0 | diff(sign(data.omega_m)) ~= 0 | ~valid(1:end-1) | ~valid(2:end)];
issues = strings(0,1);
if any(~valid), issues(end+1) = "Low-speed, invalid, saturated or nonfinite rows excluded without bridging."; end
if any(gap), issues(end+1) = "Timestamp gaps are prediction and integration boundaries."; end
if ismember(string(meta.speed_source),["sensorless","hall_interpolated"])
    issues(end+1) = "Estimated or interpolated speed can bias mechanical identification; audit its delay and resolution.";
end
if string(meta.torque_source) == "dq_model"
    issues(end+1) = "Torque uses electrical parameters; their scale error propagates to mechanical parameters.";
end
audit = struct('validRows',valid,'breakBefore',breakBefore,'runId',cumsum(breakBefore), ...
    'sampleCount',height(data),'validCount',sum(valid),'gapCount',sum(gap), ...
    'minSpeed',options.MinSpeed,'gapFactor',options.GapFactor,'issues',issues, ...
    'fingerprint',pmsm_fingerprint(data,{'t','omega_m','torque_e','load_torque'}));
if ~any(valid), error('pmsm:MechanicalNoData','No usable rows away from zero speed.'); end
end

function choice(meta,name,values)
if ~isfield(meta,name) || ~isText(meta.(name)) || ~ismember(string(meta.(name)),values)
    error('pmsm:MechanicalMetadata','meta.%s must be one of %s.',name,strjoin(values,', '));
end
end
function answer = isText(value)
answer = (isstring(value) && isscalar(value) && ~ismissing(value)) || (ischar(value) && isrow(value));
end
