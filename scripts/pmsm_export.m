function pmsm_export(result, validation, outputDirectory)
%PMSM_EXPORT Save reviewable candidates and metrics without changing a controller.
arguments
    result (1,1) struct
    validation (1,1) struct
    outputDirectory {mustBeTextScalar}
end
outputDirectory = char(outputDirectory);
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
targets = {'estimate.mat','parameters.csv','summary.json','validation_currents.csv'};
if any(cellfun(@(f) isfile(fullfile(outputDirectory,f)),targets))
    error('pmsm:OutputExists','Choose a new result folder; existing outputs are never overwritten.');
end
if ~isfield(validation,'trainingFingerprint') || ...
        validation.trainingFingerprint ~= result.dataFingerprint
    error('pmsm:ValidationMismatch','Validation must belong to this fitted result.');
end
p = result.parameters;
parameter = ["Rs";"Ld";"Lq";"psi_f"];
value = [p.Rs;p.Ld;p.Lq;p.psi_f];
unit = ["ohm";"H";"H";"Wb"];
source = repmat("estimated",4,1);
fixedNames = result.fixedNames;
if result.model == "spmsm" && ismember("L",fixedNames)
    fixedNames = [fixedNames,"Ld","Lq"];
end
source(ismember(parameter,fixedNames)) = "fixed_prior";
source(~isfinite(value)) = "not_identified";
writetable(table(parameter,value,unit,source),fullfile(outputDirectory,'parameters.csv'));
save(fullfile(outputDirectory,'estimate.mat'),'result','validation');
summary = struct('schemaVersion',"1.0",'fitStatus',result.status, ...
    'parameters',p,'parameterSources',source,'model',result.model, ...
    'diagnostics',result.diagnostics,'trainingMetadata',result.metadata, ...
    'validationStatus',validation.status,'validationMetadata',validation.metadata, ...
    'validationRMSEAmps',validation.rmseAmps, ...
    'validationMaxRMSEAmps',validation.maxRMSEAmps, ...
    'trainingFingerprint',result.dataFingerprint, ...
    'validationFingerprint',validation.dataFingerprint, ...
    'issues',[result.audit.issues;validation.audit.issues], ...
    'limitations',[result.limitations;validation.limitations]);
file = fopen(fullfile(outputDirectory,'summary.json'),'w','n','UTF-8');
if file < 0
    error('pmsm:OutputFile','Could not open summary.json.');
end
cleanup = onCleanup(@() fclose(file));
fprintf(file,'%s',jsonencode(summary,PrettyPrint=true));
measured = validation.measuredCurrents;
predicted = validation.predictedCurrents;
currents = table(validation.t,measured(:,1),measured(:,2),predicted(:,1),predicted(:,2), ...
    VariableNames={'t','id_measured','iq_measured','id_predicted','iq_predicted'});
writetable(currents,fullfile(outputDirectory,'validation_currents.csv'));
end
