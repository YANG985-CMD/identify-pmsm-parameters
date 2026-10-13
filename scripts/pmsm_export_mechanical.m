function pmsm_export_mechanical(result,validation,outputDirectory)
%PMSM_EXPORT_MECHANICAL Export mechanical candidates without controller writes.
arguments
    result (1,1) struct
    validation (1,1) struct
    outputDirectory {mustBeTextScalar}
end
if isfolder(outputDirectory) || isfile(outputDirectory)
    error('pmsm:OutputExists','Choose a new mechanical output folder.');
end
if validation.trainingFingerprint ~= result.dataFingerprint || validation.frictionFingerprint ~= result.friction.dataFingerprint
    error('pmsm:ValidationMismatch','Validation must belong to both identification stages.');
end
mkdir(outputDirectory);
parameter = ["J";"B";"Tc"];
value = [result.parameters.J;result.parameters.B;result.parameters.Tc];
unit = ["kg*m^2";"N*m*s/rad";"N*m"];
source = ["dynamic_integral_fit";"separate_steady_fit";"separate_steady_fit"];
writetable(table(parameter,value,unit,source),fullfile(outputDirectory,'parameters.csv'));
save(fullfile(outputDirectory,'estimate.mat'),'result','validation');
summary = struct('schemaVersion',"1.0",'fitStatus',result.status,'parameters',result.parameters, ...
    'trainingMetadata',result.metadata,'frictionMetadata',result.friction.metadata, ...
    'diagnostics',result.diagnostics,'frictionDiagnostics',result.friction.diagnostics, ...
    'validationStatus',validation.status,'validationRMSEradPerSecond',validation.rmseRadPerSecond, ...
    'validationMaxRMSEradPerSecond',validation.maxRMSE,'validationMetadata',validation.metadata, ...
    'trainingFingerprint',result.dataFingerprint,'frictionFingerprint',result.friction.dataFingerprint, ...
    'validationFingerprint',validation.dataFingerprint,'limitations',[result.limitations;validation.limitations]);
handle = fopen(fullfile(outputDirectory,'summary.json'),'w','n','UTF-8');
if handle < 0, error('pmsm:OutputFile','Cannot create mechanical summary.'); end
cleanup = onCleanup(@() fclose(handle)); fprintf(handle,'%s',jsonencode(summary,PrettyPrint=true));
writetable(table(validation.t,validation.measuredSpeed,validation.predictedSpeed, ...
    VariableNames={'t','omega_measured_rad_s','omega_predicted_rad_s'}), ...
    fullfile(outputDirectory,'validation_speed.csv'));
end
