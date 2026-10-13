function [result, validation] = pmsm_identify_capture(trainingFolder, validationFolder, outputFolder, options)
%PMSM_IDENTIFY_CAPTURE Verify capture integrity, fit, independently validate and export.
arguments
    trainingFolder {mustBeTextScalar}
    validationFolder {mustBeTextScalar}
    outputFolder {mustBeTextScalar}
    options.Model {mustBeTextScalar} = "ipmsm"
    options.WindowSamples (1,1) double = 20
    options.Fixed (1,1) struct = struct()
    options.MaxCondition (1,1) double = 1e6
    options.MaxRMSE (1,2) double = [Inf,Inf]
end
[trainingSource,trainingMeta] = loadCapture(trainingFolder);
[validationSource,validationMeta] = loadCapture(validationFolder);
result = pmsm_identify_electrical(trainingSource,trainingMeta, ...
    Model=options.Model,WindowSamples=options.WindowSamples, ...
    Fixed=options.Fixed,MaxCondition=options.MaxCondition);
if result.status ~= "estimated_unvalidated"
    error('pmsm:CaptureFitRejected', ...
        'Capture fit status is %s; inspect audit and excitation before exporting candidates.',result.status);
end
validation = pmsm_validate_electrical(result,validationSource,validationMeta, ...
    MaxRMSE=options.MaxRMSE);
pmsm_export(result,validation,outputFolder);
end

function [source,meta] = loadCapture(folder)
manifestFile = fullfile(folder,'capture.json');
if ~isfile(manifestFile)
    error('pmsm:CaptureManifest','Missing capture.json.');
end
manifest = jsondecode(fileread(manifestFile));
if ~isfield(manifest,'schema_version') || string(manifest.schema_version) ~= "1.0" || ...
        ~isfield(manifest,'protocol') || string(manifest.protocol) ~= "PMI1" || ...
        ~isfield(manifest,'status') || string(manifest.status) ~= "captured" || ...
        ~isfield(manifest,'sha256')
    error('pmsm:CaptureManifest','Require a completed PMI1 capture manifest.');
end
names = {'raw.bin','samples.csv','meta.json'};
for k = 1:numel(names)
    field = matlab.lang.makeValidName(names{k},ReplacementStyle='underscore');
    file = fullfile(folder,names{k});
    if ~isfile(file) || ~isfield(manifest.sha256,field) || ...
            string(manifest.sha256.(field)) ~= fileHash(file)
        error('pmsm:CaptureIntegrity','Capture file is missing or changed: %s.',names{k});
    end
end
meta = jsondecode(fileread(fullfile(folder,'meta.json')));
meta.capture_provenance = manifest;
source = fullfile(folder,'samples.csv');
end

function value = fileHash(file)
handle = fopen(file,'rb');
if handle < 0
    error('pmsm:CaptureIntegrity','Cannot read capture file.');
end
cleanup = onCleanup(@() fclose(handle));
digest = java.security.MessageDigest.getInstance('SHA-256');
while ~feof(handle)
    chunk = fread(handle,1048576,'*uint8');
    if ~isempty(chunk)
        digest.update(typecast(chunk,'int8'));
    end
end
bytes = typecast(digest.digest(),'uint8');
value = string(lower(reshape(dec2hex(bytes,2).',1,[])));
end
