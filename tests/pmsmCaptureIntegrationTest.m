classdef pmsmCaptureIntegrationTest < matlab.unittest.TestCase
    % Capture-file integrity and offline numerical behavior, without hardware.
    properties
        Folder
    end
    methods (TestMethodSetup)
        function prepare(testCase)
            scripts = fullfile(fileparts(fileparts(mfilename('fullpath'))),'scripts');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(scripts));
            root = getenv('PMSM_SKILL_TMPDIR');
            if isempty(root)
                root = tempdir;
            end
            if ~isfolder(root)
                mkdir(root);
            end
            testCase.Folder = tempname(root);
            mkdir(testCase.Folder);
            testCase.addTeardown(@() cleanFixture(testCase.Folder));
            [data,meta] = pmsm_simulated_experiment();
            writeCapture(fullfile(testCase.Folder,'train'),data,meta);
            [data,meta] = pmsm_simulated_experiment(ExperimentID="capture-holdout",Phase=0.8);
            writeCapture(fullfile(testCase.Folder,'holdout'),data,meta);
        end
    end
    methods (Test)
        function identifyAndExportVerifiedCaptures(testCase)
            [r,v] = pmsm_identify_capture(fullfile(testCase.Folder,'train'), ...
                fullfile(testCase.Folder,'holdout'),fullfile(testCase.Folder,'candidate'), ...
                WindowSamples=10);
            testCase.verifyEqual(r.parameterVector,[0.7;0.004;0.006;0.03],RelTol=0.005);
            testCase.verifyEqual(v.status,"metrics_only");
            testCase.verifyTrue(isfile(fullfile(testCase.Folder,'candidate','summary.json')));
            testCase.verifyEqual(string(r.metadata.capture_provenance.transport.kind),"matlab_test_fixture");
        end
        function rejectFailedCapture(testCase)
            file = fullfile(testCase.Folder,'train','capture.json');
            manifest = jsondecode(fileread(file));
            manifest.status = 'capture_failed';
            writeJson(file,manifest);
            testCase.verifyError(@() runPair(testCase.Folder),'pmsm:CaptureManifest');
        end
        function rejectChangedCsv(testCase)
            file = fullfile(testCase.Folder,'train','samples.csv');
            handle = fopen(file,'a');
            fprintf(handle,'\n');
            fclose(handle);
            testCase.verifyError(@() runPair(testCase.Folder),'pmsm:CaptureIntegrity');
        end
        function rejectChangedMetadata(testCase)
            file = fullfile(testCase.Folder,'train','meta.json');
            meta = jsondecode(fileread(file));
            meta.experiment_id = 'renamed-after-capture';
            writeJson(file,meta);
            testCase.verifyError(@() runPair(testCase.Folder),'pmsm:CaptureIntegrity');
        end
        function rejectMissingRawRecord(testCase)
            delete(fullfile(testCase.Folder,'train','raw.bin'));
            testCase.verifyError(@() runPair(testCase.Folder),'pmsm:CaptureIntegrity');
        end
        function rejectSameExperiment(testCase)
            train = fullfile(testCase.Folder,'train');
            testCase.verifyError(@() pmsm_identify_capture(train,train, ...
                fullfile(testCase.Folder,'candidate')),'pmsm:ValidationLeakage');
        end
    end
end

function runPair(folder)
pmsm_identify_capture(fullfile(folder,'train'),fullfile(folder,'holdout'), ...
    fullfile(folder,'candidate'),WindowSamples=10);
end

function writeCapture(folder,data,meta)
mkdir(folder);
writetable(data,fullfile(folder,'samples.csv'));
writeJson(fullfile(folder,'meta.json'),meta);
handle = fopen(fullfile(folder,'raw.bin'),'wb');
% A deliberately labelled integrity fixture; wire decoding is tested in Python.
fwrite(handle,uint8('matlab-test-fixture'),'uint8');
fclose(handle);
names = {'raw.bin','samples.csv','meta.json'};
hashes = containers.Map();
for k = 1:numel(names)
    handle = fopen(fullfile(folder,names{k}),'rb');
    bytes = fread(handle,Inf,'*uint8');
    fclose(handle);
    digest = java.security.MessageDigest.getInstance('SHA-256');
    digest.update(typecast(bytes,'int8'));
    hashes(names{k}) = lower(reshape(dec2hex(typecast(digest.digest(),'uint8'),2).',1,[]));
end
manifest = struct('schema_version','1.0','protocol','PMI1','status','captured', ...
    'transport',struct('kind','matlab_test_fixture'),'sha256',hashes);
writeJson(fullfile(folder,'capture.json'),manifest);
end

function writeJson(file,value)
handle = fopen(file,'w','n','UTF-8');
cleanup = onCleanup(@() fclose(handle));
fprintf(handle,'%s',jsonencode(value));
end

function cleanFixture(folder)
subfolders = {'train','holdout','candidate'};
files = {'raw.bin','samples.csv','meta.json','capture.json', ...
    'estimate.mat','parameters.csv','summary.json','validation_currents.csv'};
for k = 1:numel(subfolders)
    child = fullfile(folder,subfolders{k});
    for j = 1:numel(files)
        file = fullfile(child,files{j});
        if isfile(file)
            delete(file);
        end
    end
    if isfolder(child)
        rmdir(child);
    end
end
if isfolder(folder)
    rmdir(folder);
end
end
