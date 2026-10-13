classdef pmsmMechanicalTest < matlab.unittest.TestCase
    % Mechanical public behavior with an independent differential plant.
    properties
        Steady
        SteadyMeta
        Friction
        Dynamic
        DynamicMeta
        Candidate
        Holdout
        HoldoutMeta
        Validation
        DQ
        DQMeta
        Electrical
    end
    methods (TestClassSetup)
        function prepare(testCase)
            testCase.applyFixture(matlab.unittest.fixtures.PathFixture(fullfile(fileparts(fileparts(mfilename('fullpath'))),'scripts')));
            [testCase.Steady,testCase.SteadyMeta] = pmsm_mechanical_synthetic_experiment("friction_steady",ExperimentID="friction");
            testCase.Friction = pmsm_identify_friction(testCase.Steady,testCase.SteadyMeta);
            [testCase.Dynamic,testCase.DynamicMeta] = pmsm_mechanical_synthetic_experiment("mechanical_dynamic",ExperimentID="dynamic");
            testCase.Candidate = pmsm_identify_mechanical(testCase.Dynamic,testCase.DynamicMeta,testCase.Friction);
            [testCase.Holdout,testCase.HoldoutMeta] = pmsm_mechanical_synthetic_experiment("mechanical_dynamic",ExperimentID="holdout",Phase=0.8);
            testCase.Validation = pmsm_validate_mechanical(testCase.Candidate,testCase.Holdout,testCase.HoldoutMeta,MaxRMSE=0.1);
            [testCase.DQ,testCase.DQMeta] = pmsm_simulated_experiment(ExperimentID="dq-electrical");
            testCase.Electrical = pmsm_identify_electrical(testCase.DQ,testCase.DQMeta);
        end
    end
    methods (Test)
        function recoverFriction(testCase)
            testCase.verifyEqual(testCase.Friction.parameterVector,[0.001;0.02],AbsTol=1e-10);
            testCase.verifyEqual(testCase.Friction.diagnostics.rank,2);
        end
        function recoverInertia(testCase)
            testCase.verifyEqual(testCase.Candidate.parameters.J,0.002,AbsTol=2e-6);
            testCase.verifyEqual(testCase.Candidate.status,"estimated_unvalidated");
        end
        function predictIndependentSpeed(testCase)
            testCase.verifyEqual(testCase.Validation.status,"prediction_check_passed");
            testCase.verifyLessThan(testCase.Validation.rmseRadPerSecond,0.001);
            testCase.verifyTrue(isnan(testCase.Validation.predictedSpeed(1)));
            testCase.verifyEqual(testCase.Validation.scoredSamples,height(testCase.Holdout)-1);
        end
        function defaultMetricsOnly(testCase)
            result = pmsm_validate_mechanical(testCase.Candidate,testCase.Holdout,testCase.HoldoutMeta);
            testCase.verifyEqual(result.status,"metrics_only");
        end
        function estimateSignedUnknownConstantLoad(testCase)
            [data,meta] = pmsm_mechanical_synthetic_experiment("mechanical_dynamic",ExperimentID="negative-load",LoadTorque=-0.03);
            data.load_torque = []; meta.load_model = "constant_unknown";
            result = pmsm_identify_mechanical(data,meta,testCase.Friction);
            testCase.verifyEqual(result.parameters.J,0.002,AbsTol=2e-6);
            testCase.verifyEqual(result.parameters.trainingLoadTorque,-0.03,AbsTol=2e-6);
        end
        function rejectArbitraryUnknownLoad(testCase)
            meta = testCase.DynamicMeta; meta.load_model = "arbitrary_unknown";
            testCase.verifyError(@() pmsm_identify_mechanical(testCase.Dynamic,meta,testCase.Friction),'pmsm:MechanicalMetadata');
        end
        function requireKnownLoadForFriction(testCase)
            data = testCase.Steady; data.load_torque = [];
            meta = testCase.SteadyMeta; meta.load_model = "constant_unknown";
            testCase.verifyError(@() pmsm_identify_friction(data,meta),'pmsm:FrictionConditions');
        end
        function singleSteadySpeedCannotSeparateFriction(testCase)
            data = testCase.Steady(testCase.Steady.segment==4,:);
            result = pmsm_identify_friction(data,testCase.SteadyMeta);
            testCase.verifyEqual(result.status,"not_identifiable");
        end
        function rejectDynamicFrictionRows(testCase)
            meta = testCase.DynamicMeta; meta.experiment_type = "friction_steady";
            result = pmsm_identify_friction(testCase.Dynamic,meta);
            testCase.verifyEqual(result.status,"not_identifiable");
        end
        function constantSpeedCannotIdentifyJ(testCase)
            data = constantSpeedRecord(testCase.Dynamic);
            result = pmsm_identify_mechanical(data,testCase.DynamicMeta,testCase.Friction);
            testCase.verifyEqual(result.status,"not_identifiable");
        end
        function rejectRenamedTrainingAsValidation(testCase)
            meta = testCase.DynamicMeta; meta.experiment_id = "renamed";
            testCase.verifyError(@() pmsm_validate_mechanical(testCase.Candidate,testCase.Dynamic,meta),'pmsm:MechanicalIndependentData');
        end
        function rejectRenamedFrictionForJ(testCase)
            meta = testCase.SteadyMeta; meta.experiment_type = "mechanical_dynamic"; meta.experiment_id = "renamed";
            testCase.verifyError(@() pmsm_identify_mechanical(testCase.Steady,meta,testCase.Friction),'pmsm:MechanicalIndependentData');
        end
        function requireKnownValidationLoad(testCase)
            data = testCase.Holdout; data.load_torque = [];
            meta = testCase.HoldoutMeta; meta.load_model = "constant_unknown";
            testCase.verifyError(@() pmsm_validate_mechanical(testCase.Candidate,data,meta),'pmsm:MechanicalValidationLoad');
        end
        function rejectDifferentAttachedLoad(testCase)
            meta = testCase.HoldoutMeta; meta.configuration_id = "different-gear";
            testCase.verifyError(@() pmsm_validate_mechanical(testCase.Candidate,testCase.Holdout,meta),'pmsm:MechanicalScope');
        end
        function rejectSpeedUnits(testCase)
            meta = testCase.DynamicMeta; meta.units.omega_m = "rpm";
            testCase.verifyError(@() pmsm_identify_mechanical(testCase.Dynamic,meta,testCase.Friction),'pmsm:MechanicalUnits');
        end
        function rejectCommandTorque(testCase)
            meta = testCase.DynamicMeta; meta.torque_source = "command";
            testCase.verifyError(@() pmsm_identify_mechanical(testCase.Dynamic,meta,testCase.Friction),'pmsm:MechanicalMetadata');
        end
        function rejectMissingTorqueEvidence(testCase)
            meta = testCase.DynamicMeta; meta.torque_scale_evidence = "";
            testCase.verifyError(@() pmsm_identify_mechanical(testCase.Dynamic,meta,testCase.Friction),'pmsm:MechanicalTorqueScale');
        end
        function rejectUnverifiedTiming(testCase)
            meta = testCase.DynamicMeta; meta.time_alignment = "unverified";
            testCase.verifyError(@() pmsm_identify_mechanical(testCase.Dynamic,meta,testCase.Friction),'pmsm:MechanicalMetadata');
        end
        function rejectDuplicateTime(testCase)
            data = testCase.Dynamic; data.t(10) = data.t(9);
            testCase.verifyError(@() pmsm_identify_mechanical(data,testCase.DynamicMeta,testCase.Friction),'pmsm:MechanicalTime');
        end
        function rejectMissingActualTorque(testCase)
            data = testCase.Dynamic; data.torque_e = [];
            testCase.verifyError(@() pmsm_identify_mechanical(data,testCase.DynamicMeta,testCase.Friction),'pmsm:MechanicalMissingSignal');
        end
        function zeroSpeedOutsideFrictionDomain(testCase)
            data = testCase.Dynamic; data.omega_m(:) = 0;
            testCase.verifyError(@() pmsm_identify_mechanical(data,testCase.DynamicMeta,testCase.Friction),'pmsm:MechanicalNoData');
        end
        function doNotIgnoreUnexpectedLoadColumn(testCase)
            meta = testCase.DynamicMeta; meta.load_model = "known_zero";
            testCase.verifyError(@() pmsm_identify_mechanical(testCase.Dynamic,meta,testCase.Friction),'pmsm:MechanicalLoad');
        end
        function gapsAndFlagsAreBoundaries(testCase)
            data = testCase.Dynamic; data.valid = ones(height(data),1); data.saturated = zeros(height(data),1);
            data.valid(10) = 0; data.saturated(100) = 1; data.t(500:end) = data.t(500:end)+0.01;
            result = pmsm_identify_mechanical(data,testCase.DynamicMeta,testCase.Friction);
            testCase.verifyEqual(result.audit.gapCount,1);
            testCase.verifyEqual(result.audit.validCount,height(data)-2);
            testCase.verifyGreaterThanOrEqual(result.diagnostics.rejectedWindows,3);
        end
        function dqConversionUsesReluctanceTorque(testCase)
            [data,meta] = pmsm_mechanical_from_dq(testCase.DQ,testCase.DQMeta,testCase.Electrical,3,testCase.DynamicMeta);
            expected = 4.5*(testCase.Electrical.parameters.psi_f*testCase.DQ.iq+ ...
                (testCase.Electrical.parameters.Ld-testCase.Electrical.parameters.Lq)*testCase.DQ.id.*testCase.DQ.iq);
            testCase.verifyEqual(data.torque_e,expected,AbsTol=1e-12);
            testCase.verifyEqual(data.omega_m,testCase.DQ.omega_e/3,AbsTol=1e-12);
            testCase.verifyEqual(meta.torque_source,"dq_model");
        end
        function dqInvalidRowsRemainInvalid(testCase)
            original = testCase.DQ; original.ud(10) = NaN;
            [data,~] = pmsm_mechanical_from_dq(original,testCase.DQMeta,testCase.Electrical,3,testCase.DynamicMeta);
            testCase.verifyFalse(data.valid(10));
        end
        function sharedTorqueBiasDoesNotProveAccuracy(testCase)
            [friction,dynamic,holdout] = scaledRecords(testCase.Steady,testCase.Dynamic,testCase.Holdout);
            first = pmsm_identify_friction(friction,testCase.SteadyMeta);
            result = pmsm_identify_mechanical(dynamic,testCase.DynamicMeta,first);
            validation = pmsm_validate_mechanical(result,holdout,testCase.HoldoutMeta,MaxRMSE=0.1);
            testCase.verifyEqual(result.parameters.J,0.0022,AbsTol=2e-6);
            testCase.verifyEqual(validation.status,"prediction_check_passed");
        end
        function exportAndRefuseOverwrite(testCase)
            folder = mechanicalTestDirectory();
            testCase.addTeardown(@() cleanMechanicalTestDirectory(folder));
            output = fullfile(folder,'result');
            pmsm_export_mechanical(testCase.Candidate,testCase.Validation,output);
            summary = jsondecode(fileread(fullfile(output,'summary.json')));
            testCase.verifyEqual(summary.parameters.J,0.002,AbsTol=2e-6);
            testCase.verifyTrue(isfile(fullfile(output,'validation_speed.csv')));
            testCase.verifyError(@() pmsm_export_mechanical(testCase.Candidate,testCase.Validation,output),'pmsm:OutputExists');
        end
    end
end

function data = constantSpeedRecord(data)
data.omega_m(:) = 35; data.torque_e(:) = 0.055;
end
function [steady,dynamic,holdout] = scaledRecords(steady,dynamic,holdout)
steady.torque_e = 1.1*steady.torque_e; dynamic.torque_e = 1.1*dynamic.torque_e; holdout.torque_e = 1.1*holdout.torque_e;
end
function folder = mechanicalTestDirectory()
root = getenv('PMSM_SKILL_TMPDIR'); if isempty(root), root = tempdir; end
if ~isfolder(root), mkdir(root); end
folder = tempname(root); mkdir(folder);
end
function cleanMechanicalTestDirectory(folder)
output = fullfile(folder,'result');
for name = {'estimate.mat','parameters.csv','summary.json','validation_speed.csv'}
    file = fullfile(output,name{1}); if isfile(file), delete(file); end
end
if isfolder(output), rmdir(output); end
if isfolder(folder), rmdir(folder); end
end
