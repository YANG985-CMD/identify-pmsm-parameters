function [data, audit] = pmsm_audit(source, meta)
%PMSM_AUDIT Validate units and provenance; retain invalid rows as barriers.
arguments
    source
    meta (1,1) struct
end
data = pmsm_load_data(source);
names = {'t','id','iq','ud','uq','omega_e'};
units = {'s','A','A','V','V','rad/s'};
for k = 1:numel(names)
    name = names{k};
    if ~ismember(name, data.Properties.VariableNames)
        error('pmsm:MissingSignal', 'Missing required measured signal: %s.', name);
    end
    value = data.(name);
    if ~isnumeric(value) || ~isreal(value) || ~iscolumn(value)
        error('pmsm:SignalType', '%s must be a real numeric column.', name);
    end
    if ~isfield(meta, 'units') || ~isstruct(meta.units) || ...
            ~isfield(meta.units, name) || ~isequal(string(meta.units.(name)), string(units{k}))
        error('pmsm:Units', 'meta.units.%s must be %s; convert explicitly first.', name, units{k});
    end
    data.(name) = double(value);
end
checkChoice(meta, 'dq_convention', "amplitude_invariant");
checkChoice(meta, 'speed_kind', "electrical");
checkChoice(meta, 'd_axis', "pm_flux");
checkChoice(meta, 'angle_source', ["encoder","hall_interpolated","sensorless","simulation"]);
checkChoice(meta, 'voltage_source', ["measured","reconstructed_compensated","command","simulation"]);
checkChoice(meta, 'time_alignment', ["verified","unverified"]);
checkChoice(meta, 'source_kind', ["measurement","simulation"]);
if ~isfield(meta,'experiment_id') || ~isText(meta.experiment_id) || strlength(string(meta.experiment_id)) == 0
    error('pmsm:Metadata', 'Provide a nonempty experiment_id for provenance.');
end
if string(meta.source_kind) == "measurement" && ...
        (string(meta.angle_source) == "simulation" || string(meta.voltage_source) == "simulation")
    error('pmsm:Metadata', 'Measurement data cannot declare simulated angle or voltage.');
end
if height(data) < 3 || any(~isfinite(data.t)) || any(diff(data.t) <= 0)
    error('pmsm:Time', 'Need at least three finite, strictly increasing timestamps.');
end
dt = diff(data.t);
medianDt = median(dt);
valid = all(isfinite(data{:,names}),2);
if ismember('valid', data.Properties.VariableNames)
    valid = valid & flag(data.valid, 'valid', height(data));
end
if ismember('saturated', data.Properties.VariableNames)
    valid = valid & ~flag(data.saturated, 'saturated', height(data));
end
segment = ones(height(data),1);
if ismember('segment', data.Properties.VariableNames)
    segment = data.segment;
    if ~isnumeric(segment) || ~isreal(segment) || ~iscolumn(segment) || any(~isfinite(segment))
        error('pmsm:Segment', 'segment must be a finite real numeric column.');
    end
end
gap = dt > 1.5*medianDt;
breakBefore = [true; gap | diff(segment) ~= 0 | ~valid(1:end-1) | ~valid(2:end)];
issues = strings(0,1);
if any(~valid)
    issues(end+1) = "Nonfinite, invalid, or saturated samples were excluded without bridging them.";
end
if any(gap)
    issues(end+1) = "Timestamp gaps were detected; windows and predictions cannot cross them.";
end
if max(abs(dt-medianDt))/medianDt > 0.05
    issues(end+1) = "Nonuniform sampling detected; integration uses actual timestamps.";
end
if string(meta.voltage_source) == "command"
    issues(end+1) = "Command voltage can contain unmodelled inverter error; estimates are provisional.";
end
if string(meta.angle_source) ~= "encoder" && string(meta.angle_source) ~= "simulation"
    issues(end+1) = "Angle interpolation or observer errors can bias the dq model.";
end
if string(meta.time_alignment) == "unverified"
    issues(end+1) = "Voltage/current timing is unverified; validate alignment before physical use.";
end
audit = struct('sampleCount',height(data),'validCount',sum(valid), ...
    'medianSamplePeriod',medianDt,'gapCount',sum(gap),'validRows',valid, ...
    'breakBefore',breakBefore,'runId',cumsum(breakBefore),'issues',issues, ...
    'metadataMeetsPreferredConditions',string(meta.time_alignment) == "verified" && ...
        string(meta.voltage_source) ~= "command" && ...
        (string(meta.angle_source) == "encoder" || string(meta.angle_source) == "simulation"));
if ~any(valid)
    error('pmsm:NoUsableData', 'No usable finite, unsaturated samples.');
end
audit.fingerprint = pmsm_fingerprint(data, names);
end

function checkChoice(meta, name, choices)
if ~isfield(meta,name) || ~isText(meta.(name)) || ~ismember(string(meta.(name)), choices)
    error('pmsm:Metadata', 'meta.%s must be one of: %s.', name, strjoin(choices, ', '));
end
end

function answer = isText(value)
answer = (isstring(value) && isscalar(value) && ~ismissing(value)) || ...
    (ischar(value) && isrow(value));
end

function result = flag(value, name, n)
if (~islogical(value) && ~isnumeric(value)) || ~isreal(value) || ...
        ~isequal(size(value),[n,1]) || any(~ismember(value,[0,1]))
    error('pmsm:Flag', '%s must be a logical or 0/1 column.', name);
end
result = logical(value);
end
