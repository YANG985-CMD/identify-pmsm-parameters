function [data,meta] = pmsm_mechanical_from_dq(source,dqMeta,electrical,polePairs,mechanicalMeta)
%PMSM_MECHANICAL_FROM_DQ Convert existing SI dq telemetry to mechanical inputs.
arguments
    source
    dqMeta (1,1) struct
    electrical (1,1) struct
    polePairs (1,1) double {mustBeFinite,mustBeInteger,mustBePositive}
    mechanicalMeta (1,1) struct
end
[original,dqAudit] = pmsm_audit(source,dqMeta);
if electrical.status ~= "estimated_unvalidated" || any(~isfinite([electrical.parameters.Ld,electrical.parameters.Lq,electrical.parameters.psi_f]))
    error('pmsm:MechanicalElectricalScale','Use a supported electrical candidate with finite Ld/Lq/psi_f.');
end
if ~isfield(mechanicalMeta,'source_kind') || string(mechanicalMeta.source_kind) ~= string(dqMeta.source_kind)
    error('pmsm:MechanicalMetadata','Electrical and mechanical source_kind must agree.');
end
if string(dqMeta.time_alignment) ~= "verified"
    error('pmsm:MechanicalMetadata','Verify current and speed timing before mechanical conversion.');
end
if string(dqMeta.source_kind) == "measurement" && string(electrical.metadata.source_kind) == "simulation"
    error('pmsm:MechanicalElectricalScale','Simulated electrical parameters cannot certify measured electromagnetic torque.');
end
p = electrical.parameters;
data = table(original.t,original.omega_e/polePairs, ...
    1.5*polePairs*(p.psi_f*original.iq+(p.Ld-p.Lq)*original.id.*original.iq), ...
    VariableNames={'t','omega_m','torque_e'});
for name = {'valid','saturated','segment','load_torque'}
    if ismember(name{1},original.Properties.VariableNames), data.(name{1}) = original.(name{1}); end
end
data.valid = dqAudit.validRows;
meta = mechanicalMeta;
meta.torque_source = "dq_model"; meta.speed_source = string(dqMeta.angle_source);
meta.units.t = "s"; meta.units.omega_m = "rad/s"; meta.units.torque_e = "N*m";
meta.torque_scale_evidence = "Amplitude-invariant dq model, electrical fingerprint "+electrical.dataFingerprint;
meta.torque_parameters = struct('polePairs',polePairs,'Ld',p.Ld,'Lq',p.Lq,'psi_f',p.psi_f, ...
    'electricalMetadata',electrical.metadata,'electricalStatus',electrical.status);
end
