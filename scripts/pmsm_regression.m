function regression = pmsm_regression(data, audit, windowSamples, strideSamples)
%PMSM_REGRESSION Build interval-average voltage regressions without derivatives.
arguments
    data table
    audit (1,1) struct
    windowSamples (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBePositive}
    strideSamples (1,1) {mustBeNumeric,mustBeReal,mustBeFinite,mustBeInteger,mustBePositive}
end
starts = (1:strideSamples:height(data)-windowSamples).';
capacity = numel(starts);
phi = zeros(2*capacity,4);
y = zeros(2*capacity,1);
interval = zeros(capacity,2);
used = 0;
for k = 1:capacity
    a = starts(k);
    b = a+windowSamples;
    if ~all(audit.validRows(a:b)) || audit.runId(a) ~= audit.runId(b)
        continue
    end
    t = data.t(a:b);
    duration = t(end)-t(1);
    id = data.id(a:b);
    iq = data.iq(a:b);
    omega = data.omega_e(a:b);
    used = used+1;
    r = 2*used-1;
    phi(r,:) = [trapz(t,id),id(end)-id(1),-trapz(t,omega.*iq),0]/duration;
    phi(r+1,:) = [trapz(t,iq),trapz(t,omega.*id),iq(end)-iq(1),trapz(t,omega)]/duration;
    y(r:r+1) = [trapz(t,data.ud(a:b));trapz(t,data.uq(a:b))]/duration;
    interval(used,:) = [a,b];
end
regression = struct('phi',phi(1:2*used,:),'y',y(1:2*used), ...
    'intervals',interval(1:used,:),'usedWindows',used, ...
    'rejectedWindows',capacity-used,'windowSamples',windowSamples, ...
    'strideSamples',strideSamples);
end
