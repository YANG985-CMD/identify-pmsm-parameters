function result = pmsm_identify_electrical(source, meta, options)
%PMSM_IDENTIFY_ELECTRICAL Estimate supported PMSM parameters with integral LS.
% Fixed parameters are explicit priors, never identified results.
arguments
    source
    meta (1,1) struct
    options.Model {mustBeTextScalar,mustBeMember(options.Model,["ipmsm","spmsm"])} = "ipmsm"
    options.WindowSamples (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBePositive} = 20
    options.StrideSamples (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBeNonnegative} = 0
    options.Fixed (1,1) struct = struct()
    options.EquationStd (1,2) {mustBeNumeric,mustBeReal,mustBeFinite,mustBePositive} = [1,1]
    options.MaxCondition (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeGreaterThan(options.MaxCondition,1)} = 1e6
end
[data,audit] = pmsm_audit(source,meta);
% Zero explicitly selects the window length; MATLAB NV defaults cannot depend on NV defaults.
if options.StrideSamples == 0
    options.StrideSamples = options.WindowSamples;
end
reg = pmsm_regression(data,audit,options.WindowSamples,options.StrideSamples);
if string(options.Model) == "spmsm"
    transform = [1,0,0;0,1,0;0,1,0;0,0,1];
    names = ["Rs","L","psi_f"];
else
    transform = eye(4);
    names = ["Rs","Ld","Lq","psi_f"];
end
phi = reg.phi*transform;
theta = nan(numel(names),1);
fixed = false(numel(names),1);
fields = fieldnames(options.Fixed);
for k = 1:numel(fields)
    j = find(names == string(fields{k}),1);
    if isempty(j)
        error('pmsm:FixedParameter', 'Unknown fixed parameter %s for model %s.',fields{k},options.Model);
    end
    value = options.Fixed.(fields{k});
    validateattributes(value,{'numeric'},{'real','finite','scalar','positive'},mfilename,fields{k});
    theta(j) = value;
    fixed(j) = true;
end
free = ~fixed;
weights = repmat(1./options.EquationStd(:), reg.usedWindows,1);
y = (reg.y-phi(:,fixed)*theta(fixed)).*weights;
matrix = phi(:,free).*weights;
scale = vecnorm(matrix,2,1);
scale(scale == 0) = 1;
scaled = matrix./scale;
rankValue = 0;
condition = Inf;
singularValues = [];
weakDirection = nan(sum(free),1);
status = "not_identifiable";
if ~any(free)
    status = "prior_only";
elseif size(scaled,1) >= sum(free)
    [~,s,v] = svd(scaled,0);
    singularValues = diag(s);
    tolerance = max(size(scaled))*eps(max(singularValues));
    rankValue = sum(singularValues > tolerance);
    weakDirection = v(:,end);
    if rankValue == sum(free)
        condition = singularValues(1)/singularValues(end);
        if condition <= options.MaxCondition
            theta(free) = (scaled\y)./scale.';
            status = "estimated_unvalidated";
            if any(theta <= 0) || any(~isfinite(theta))
                status = "nonphysical";
            end
        else
            status = "ill_conditioned";
        end
    end
end
% Avoid 0*NaN contamination when expanding a rejected partial solution.
expanded = nan(4,1);
for k = 1:4
    expanded(k) = theta(find(transform(k,:) ~= 0,1));
end
parameters = struct('Rs',expanded(1),'Ld',expanded(2),'Lq',expanded(3),'psi_f',expanded(4));
residual = nan(size(reg.y));
if all(isfinite(theta))
    residual = reg.y-phi*theta;
end
result = struct('schemaVersion',"1.0",'algorithm',"integral_weighted_ls", ...
    'model',string(options.Model),'status',status,'parameters',parameters, ...
    'parameterNames',names,'parameterVector',theta,'fixedNames',names(fixed), ...
    'estimatedNames',names(free),'fixedPriors',options.Fixed,'metadata',meta, ...
    'audit',audit,'options',options,'dataFingerprint',audit.fingerprint, ...
    'diagnostics',struct('rank',rankValue,'unknownCount',sum(free), ...
       'scaledCondition',condition,'singularValues',singularValues, ...
       'columnScales',scale,'weakDirectionScaled',weakDirection, ...
       'usedWindows',reg.usedWindows,'rejectedWindows',reg.rejectedWindows, ...
       'residualRMSEVolts',[axisRmse(residual,1),axisRmse(residual,2)]), ...
    'limitations',"No parameter confidence interval or inverter compensation is inferred. Fixed values are priors. Physical accuracy needs independent reference measurements.");
end

function value = axisRmse(residual, axis)
values = residual(axis:2:end);
if isempty(values) || any(~isfinite(values))
    value = NaN;
else
    value = sqrt(mean(values.^2));
end
end
