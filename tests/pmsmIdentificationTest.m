classdef pmsmIdentificationTest < matlab.unittest.TestCase
    % Public-behavior tests using differential plant simulation and bad records.
    properties
        Data
        Meta
        Truth
        Holdout
        HoldoutMeta
        Estimate
    end
    methods (TestClassSetup)
        function prepareExperiments(testCase)
            folder = fullfile(fileparts(fileparts(mfilename('fullpath'))),'scripts');
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(folder));
            [testCase.Data,testCase.Meta,testCase.Truth] = pmsm_simulated_experiment();
            [testCase.Holdout,testCase.HoldoutMeta] = pmsm_simulated_experiment( ...
                ExperimentID="synthetic-holdout",Phase=0.8);
            testCase.Estimate = pmsm_identify_electrical(testCase.Data,testCase.Meta,WindowSamples=10);
        end
    end
    methods (Test)
        function recoverSalientParameters(testCase)
            r = testCase.Estimate;
            testCase.verifyEqual(r.status,"estimated_unvalidated");
            testCase.verifyEqual(r.parameterVector,[0.7;0.004;0.006;0.03],RelTol=0.005);
            testCase.verifyEqual(r.diagnostics.rank,4);
        end
        function recoverNonsalientParameters(testCase)
            [data,meta] = pmsm_simulated_experiment(Salient=false);
            r = pmsm_identify_electrical(data,meta,Model="spmsm",WindowSamples=10);
            testCase.verifyEqual(r.status,"estimated_unvalidated");
            testCase.verifyEqual(r.parameterVector,[0.7;0.004;0.03],RelTol=0.005);
            testCase.verifyEqual(r.parameters.Ld,r.parameters.Lq,AbsTol=1e-14);
        end
        function tolerateSmallMeasurementNoise(testCase)
            [data,meta] = pmsm_simulated_experiment(CurrentNoiseStd=0.002,VoltageNoiseStd=0.002);
            r = pmsm_identify_electrical(data,meta,WindowSamples=20);
            testCase.verifyEqual(r.status,"estimated_unvalidated");
            testCase.verifyEqual(r.parameterVector,[0.7;0.004;0.006;0.03],RelTol=0.02);
        end
        function rejectSteadyUnexcitedData(testCase)
            data = steadyRecord(testCase.Data,testCase.Truth);
            r = pmsm_identify_electrical(data,testCase.Meta);
            testCase.verifyEqual(r.status,"not_identifiable");
            testCase.verifyTrue(all(isnan(r.parameterVector)));
        end
        function identifyOnlyWithDeclaredPriors(testCase)
            data = steadyRecord(testCase.Data,testCase.Truth);
            r = pmsm_identify_electrical(data,testCase.Meta,Fixed=struct('Rs',0.7,'Ld',0.004));
            testCase.verifyEqual(r.status,"estimated_unvalidated");
            testCase.verifyEqual(r.parameterVector,[0.7;0.004;0.006;0.03],RelTol=1e-9);
            testCase.verifyEqual(r.fixedNames,["Rs","Ld"]);
        end
        function rejectMissingVoltage(testCase)
            data = removevars(testCase.Data,'ud');
            testCase.verifyError(@() pmsm_identify_electrical(data,testCase.Meta),'pmsm:MissingSignal');
        end
        function rejectMechanicalSpeedUnits(testCase)
            meta = testCase.Meta;
            meta.units.omega_e = "rpm";
            testCase.verifyError(@() pmsm_identify_electrical(testCase.Data,meta),'pmsm:Units');
        end
        function rejectNonmonotoneTime(testCase)
            data = testCase.Data;
            data.t(100) = data.t(99);
            testCase.verifyError(@() pmsm_identify_electrical(data,testCase.Meta),'pmsm:Time');
        end
        function preserveBarriersForBadSamplesAndGaps(testCase)
            data = testCase.Data;
            data.id(50) = NaN;
            data.saturated = false(height(data),1);
            data.saturated(150) = true;
            data.t(1001:end) = data.t(1001:end)+0.02;
            r = pmsm_identify_electrical(data,testCase.Meta,WindowSamples=20);
            testCase.verifyEqual(r.audit.gapCount,1);
            testCase.verifyEqual(r.audit.validCount,height(data)-2);
            testCase.verifyGreaterThanOrEqual(r.diagnostics.rejectedWindows,3);
            testCase.verifyEqual(r.parameterVector,[0.7;0.004;0.006;0.03],RelTol=0.005);
        end
        function predictIndependentExperiment(testCase)
            v = pmsm_validate_electrical(testCase.Estimate,testCase.Holdout, ...
                testCase.HoldoutMeta,MaxRMSE=[0.01,0.01]);
            testCase.verifyEqual(v.status,"prediction_check_passed");
            testCase.verifyLessThan(max(v.rmseAmps),0.01);
            testCase.verifyEqual(v.scoredSamples,height(testCase.Holdout)-1);
        end
        function rejectTrainingDataUnderAnotherName(testCase)
            meta = testCase.Meta;
            meta.experiment_id = "renamed-train";
            testCase.verifyError(@() pmsm_validate_electrical(testCase.Estimate, ...
                testCase.Data,meta),'pmsm:ValidationLeakage');
        end
        function reportFailedPredictionAfterVoltageBias(testCase)
            data = testCase.Holdout;
            data.uq = data.uq+0.5;
            v = pmsm_validate_electrical(testCase.Estimate,data, ...
                testCase.HoldoutMeta,MaxRMSE=[0.01,0.01]);
            testCase.verifyEqual(v.status,"prediction_check_failed");
        end
        function noDefaultAccuracyClaim(testCase)
            v = pmsm_validate_electrical(testCase.Estimate,testCase.Holdout,testCase.HoldoutMeta);
            testCase.verifyEqual(v.status,"metrics_only");
        end
        function provenanceWarningForCommandVoltage(testCase)
            meta = testCase.Meta;
            meta.voltage_source = "command";
            [~,audit] = pmsm_audit(testCase.Data,meta);
            testCase.verifyFalse(audit.metadataMeetsPreferredConditions);
            testCase.verifyNotEmpty(audit.issues);
        end
        function priorOnlyDoesNotClaimIdentification(testCase)
            r = pmsm_identify_electrical(testCase.Data,testCase.Meta,Fixed=testCase.Truth);
            testCase.verifyEqual(r.status,"prior_only");
        end
        function rejectIllConditionedRequest(testCase)
            r = pmsm_identify_electrical(testCase.Data,testCase.Meta,MaxCondition=1.01);
            testCase.verifyEqual(r.status,"ill_conditioned");
            testCase.verifyTrue(all(isnan(r.parameterVector)));
        end
        function validationDoesNotBridgeGaps(testCase)
            data = testCase.Holdout;
            data.t(1001:end) = data.t(1001:end)+0.02;
            data.id(1500) = NaN;
            v = pmsm_validate_electrical(testCase.Estimate,data,testCase.HoldoutMeta,MaxRMSE=[0.01,0.01]);
            testCase.verifyEqual(v.continuousRuns,3);
            testCase.verifyEqual(v.scoredSamples,height(data)-4);
            testCase.verifyEqual(v.status,"prediction_check_passed");
        end
        function explicitSegmentsCreatePredictionBoundaries(testCase)
            data = testCase.Holdout;
            data.segment = [ones(1000,1);2*ones(height(data)-1000,1)];
            v = pmsm_validate_electrical(testCase.Estimate,data,testCase.HoldoutMeta);
            testCase.verifyEqual(v.continuousRuns,2);
            testCase.verifyEqual(v.scoredSamples,height(data)-2);
        end
        function readCsvAndMatInputs(testCase)
            folder = createTestFolder();
            testCase.addTeardown(@() cleanTestFolder(folder));
            data = testCase.Data;
            writetable(data,fullfile(folder,'samples.csv'));
            save(fullfile(folder,'samples.mat'),'data');
            fromCsv = pmsm_identify_electrical(fullfile(folder,'samples.csv'),testCase.Meta,WindowSamples=10);
            fromMat = pmsm_identify_electrical(fullfile(folder,'samples.mat'),testCase.Meta,WindowSamples=10);
            testCase.verifyEqual(fromCsv.parameterVector,testCase.Estimate.parameterVector,RelTol=1e-6);
            testCase.verifyEqual(fromMat.parameterVector,testCase.Estimate.parameterVector,AbsTol=1e-12);
        end
        function exportReviewableResultsAndRefuseOverwrite(testCase)
            folder = createTestFolder();
            testCase.addTeardown(@() cleanTestFolder(folder));
            v = pmsm_validate_electrical(testCase.Estimate,testCase.Holdout,testCase.HoldoutMeta,MaxRMSE=[0.01,0.01]);
            pmsm_export(testCase.Estimate,v,folder);
            summary = jsondecode(fileread(fullfile(folder,'summary.json')));
            testCase.verifyEqual(summary.fitStatus,'estimated_unvalidated');
            testCase.verifyEqual(summary.validationStatus,'prediction_check_passed');
            testCase.verifyTrue(isfile(fullfile(folder,'estimate.mat')));
            testCase.verifyError(@() pmsm_export(testCase.Estimate,v,folder),'pmsm:OutputExists');
        end
        function rejectMalformedFlags(testCase)
            data = testCase.Data;
            data.saturated = repmat(2,height(data),1);
            testCase.verifyError(@() pmsm_audit(data,testCase.Meta),'pmsm:Flag');
        end
        function rejectImpossibleMeasurementProvenance(testCase)
            meta = testCase.Meta;
            meta.source_kind = "measurement";
            testCase.verifyError(@() pmsm_audit(testCase.Data,meta),'pmsm:Metadata');
        end
    end
end

function data = steadyRecord(template,p)
data = template;
data.id(:) = 0;
data.iq(:) = 2;
data.omega_e(:) = 150;
data.ud(:) = -150*p.Lq*2;
data.uq(:) = p.Rs*2+150*p.psi_f;
end

function folder = createTestFolder()
root = getenv('PMSM_SKILL_TMPDIR');
if isempty(root)
    root = tempdir;
end
if ~isfolder(root)
    mkdir(root);
end
folder = tempname(root);
mkdir(folder);
end

function cleanTestFolder(folder)
% Delete only known files created by these I/O tests; never recursively delete.
files = {'samples.csv','samples.mat','estimate.mat','parameters.csv', ...
    'summary.json','validation_currents.csv'};
for k = 1:numel(files)
    path = fullfile(folder,files{k});
    if isfile(path)
        delete(path);
    end
end
if isfolder(folder)
    rmdir(folder);
end
end
