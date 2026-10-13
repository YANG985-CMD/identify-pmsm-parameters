function report = pmsm_run_simulink_benchmark(outputDirectory)
%PMSM_RUN_SIMULINK_BENCHMARK Reproducible comparison, no hardware access.
arguments
    outputDirectory {mustBeTextScalar}
end
if isfolder(outputDirectory) || isfile(outputDirectory)
    error('pmsm:OutputExists','Choose a new benchmark output directory.');
end
folder = fileparts(mfilename('fullpath'));
previousPath = path;
pathCleanup = onCleanup(@() path(previousPath));
addpath(folder,fullfile(fileparts(folder),'scripts'));
temporaryRoot = getenv('PMSM_SKILL_TMPDIR');
if isempty(temporaryRoot)
    temporaryRoot = tempdir;
end
if ~isfolder(temporaryRoot)
    mkdir(temporaryRoot);
end
previousFileGen = Simulink.fileGenControl('getConfig');
fileGenCleanup = onCleanup(@() Simulink.fileGenControl('setConfig','config',previousFileGen));
Simulink.fileGenControl('set','CacheFolder',fullfile(temporaryRoot,'pmsm_bench_cache'), ...
    'CodeGenFolder',fullfile(temporaryRoot,'pmsm_bench_codegen'),'createDir',true);
mkdir(outputDirectory);
bench = pmsm_bench_defaults();
current = [-logspace(log10(8),log10(0.01),40),0,logspace(log10(0.01),log10(8),40)].';
% Labels are generated only for this synthetic calibration experiment.
% Motor parameter estimation never sees the true inverter formula or motor truth.
calibrationVoltage = bench.VoltageDrop*tanh(current/bench.ZeroCurrent)+bench.ResistanceDrop*current;
oldRng = rng;
rng(43,'twister');
calibrationVoltage = calibrationVoltage+0.001*randn(size(current));
rng(oldRng);
network = pmsm_fit_voltage_network(current,calibrationVoltage);
unseenCurrent = linspace(-7.9,7.9,500).';
unseenTruth = bench.VoltageDrop*tanh(unseenCurrent/bench.ZeroCurrent)+bench.ResistanceDrop*unseenCurrent;
calibrationHoldoutRMSE = sqrt(mean((pmsm_predict_voltage_error(network,unseenCurrent)-unseenTruth).^2));
writetable(table(current,calibrationVoltage),fullfile(outputDirectory,'calibration.csv'));
writeJson(fullfile(outputDirectory,'voltage-network.json'),network);

ideal = bench; ideal.VoltageDrop = 0; ideal.ResistanceDrop = 0;
idealTrain = pmsm_simulate_bench(ideal,"ideal-train");
ideal.Phase = 0.8;
idealHoldout = pmsm_simulate_bench(ideal,"ideal-holdout");
nonlinearTrain = pmsm_simulate_bench(bench,"nonlinear-train");
holdoutBench = bench; holdoutBench.Phase = 0.8;
nonlinearHoldout = pmsm_simulate_bench(holdoutBench,"nonlinear-holdout");
oracleTrain = actualVoltageRecord(nonlinearTrain);
oracleHoldout = actualVoltageRecord(nonlinearHoldout);
correctedTrain = pmsm_compensate_record(nonlinearTrain,network);
correctedHoldout = pmsm_compensate_record(nonlinearHoldout,network);
noisyTrain = pmsm_simulate_bench(bench,"noisy-train",CurrentNoiseStd=0.005,VoltageNoiseStd=0.005,Seed=7);
noisyHoldout = pmsm_simulate_bench(holdoutBench,"noisy-holdout",CurrentNoiseStd=0.005,VoltageNoiseStd=0.005,Seed=8);
noisyTrain = pmsm_compensate_record(noisyTrain,network);
noisyHoldout = pmsm_compensate_record(noisyHoldout,network);
driftBench = bench; driftBench.VoltageDrop = 0.5;
driftTrain = pmsm_compensate_record(pmsm_simulate_bench(driftBench,"drift-train"),network);
driftBench.Phase = 0.8;
driftHoldout = pmsm_compensate_record(pmsm_simulate_bench(driftBench,"drift-holdout"),network);

names = ["ideal","command_voltage","actual_voltage_oracle", ...
    "ffnn_compensated","ffnn_with_noise","stale_calibration"];
training = {idealTrain,nonlinearTrain,oracleTrain,correctedTrain,noisyTrain,driftTrain};
holdout = {idealHoldout,nonlinearHoldout,oracleHoldout,correctedHoldout,noisyHoldout,driftHoldout};
estimates = cell(numel(names),1);
validations = cell(numel(names),1);
parameterValues = nan(numel(names),4);
errorPercent = nan(numel(names),4);
rmse = nan(numel(names),2);
rankValue = nan(numel(names),1);
condition = nan(numel(names),1);
fitStatus = strings(numel(names),1);
validationStatus = strings(numel(names),1);
truth = [bench.Rs,bench.Ld,bench.Lq,bench.Flux];
for k = 1:numel(names)
    estimates{k} = pmsm_identify_electrical(training{k}.data,training{k}.meta,WindowSamples=10);
    fitStatus(k) = estimates{k}.status;
    parameterValues(k,:) = estimates{k}.parameterVector.';
    errorPercent(k,:) = 100*(parameterValues(k,:)-truth)./truth;
    rankValue(k) = estimates{k}.diagnostics.rank;
    condition(k) = estimates{k}.diagnostics.scaledCondition;
    if fitStatus(k) == "estimated_unvalidated"
        % 0.05 A is explicitly a synthetic benchmark criterion, not a device limit.
        validations{k} = pmsm_validate_electrical(estimates{k},holdout{k}.data,holdout{k}.meta,MaxRMSE=[0.05,0.05]);
        rmse(k,:) = validations{k}.rmseAmps;
        validationStatus(k) = validations{k}.status;
    else
        validationStatus(k) = "fit_rejected";
    end
end
summary = table(names.',fitStatus,validationStatus,parameterValues(:,1),parameterValues(:,2), ...
    parameterValues(:,3),parameterValues(:,4),errorPercent(:,1),errorPercent(:,2), ...
    errorPercent(:,3),errorPercent(:,4),rmse(:,1),rmse(:,2),rankValue,condition, ...
    VariableNames={'scenario','fit_status','validation_status','Rs_ohm','Ld_H','Lq_H','flux_Wb', ...
    'Rs_error_percent','Ld_error_percent','Lq_error_percent','flux_error_percent', ...
    'id_rmse_A','iq_rmse_A','rank','scaled_condition'});
writetable(summary,fullfile(outputDirectory,'benchmark_summary.csv'));

% Exact steady state: repeated rows add no independent identification information.
weakBench = ideal; weakBench.Phase = 0; weakBench.SpeedAmplitude = 0;
weakBench.DVoltageAmplitude = [0,0]; weakBench.QVoltageAmplitude = [0,0];
steady = [weakBench.Rs,-weakBench.SpeedBias*weakBench.Lq; ...
    weakBench.SpeedBias*weakBench.Ld,weakBench.Rs]\ ...
    [weakBench.DVoltageBias;weakBench.QVoltageBias-weakBench.SpeedBias*weakBench.Flux];
weakBench.InitialDCurrent = steady(1); weakBench.InitialQCurrent = steady(2);
weakRecord = pmsm_simulate_bench(weakBench,"no-excitation");
weakFit = pmsm_identify_electrical(weakRecord.data,weakRecord.meta,WindowSamples=10);

fineBench = bench; fineBench.SolverStep = bench.SolverStep/2;
fineRecord = pmsm_simulate_bench(fineBench,"half-solver-step");
solverRMSE = sqrt(mean((fineRecord.data{:,{'id','iq'}}-nonlinearTrain.data{:,{'id','iq'}}).^2,1));
maxError = max(abs(errorPercent),[],2);
checks = struct('calibrationHoldoutBelow10mV',calibrationHoldoutRMSE < 0.01, ...
    'idealParameterErrorBelowPoint2Percent',maxError(1) < 0.2, ...
    'oracleParameterErrorBelowPoint2Percent',maxError(3) < 0.2, ...
    'compensatedErrorBelow1Percent',maxError(4) < 1, ...
    'compensationImprovesMaxErrorTenfold',maxError(4) < maxError(2)/10, ...
    'compensatedHoldoutBelow20mA',all(rmse(4,:) < 0.02), ...
    'noisyCompensatedErrorBelow3Percent',maxError(5) < 3, ...
    'staleCalibrationDegradesError',maxError(6) > 5*maxError(4), ...
    'weakDataRejected',ismember(weakFit.status,["not_identifiable","ill_conditioned"]), ...
    'halvedSolverStepDifferenceBelowPoint1mA',all(solverRMSE < 1e-4));
report = struct('schemaVersion',"1.0",'kind',"synthetic_simulink_benchmark", ...
    'generatedAtUTC',string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    'matlabVersion',version,'model',"pmsm_id_bench.slx",'modelSHA256',fileHash(fullfile(folder,'pmsm_id_bench.slx')), ...
    'truth',nonlinearTrain.truth,'bench',bench,'windowSamples',10, ...
    'validationMaxRMSEAmps',[0.05,0.05],'holdoutExcitationPhaseRad',0.8, ...
    'noise',struct('currentStdAmps',0.005,'commandVoltageStdVolts',0.005, ...
        'trainingSeed',7,'holdoutSeed',8,'calibrationVoltageStdVolts',0.001,'calibrationSeed',43), ...
    'driftVoltageDropVolts',0.5, ...
    'calibration',struct('trainingRMSEVolts',network.calibrationRMSEVolts, ...
        'heldoutRMSEVolts',calibrationHoldoutRMSE,'source',"separate_synthetic_phase_sweep"), ...
    'cases',table2struct(summary),'checks',checks, ...
    'allChecksPassed',all(structfun(@(value) logical(value),checks)), ...
    'weakExcitationStatus',weakFit.status,'halvedSolverStepRMSEAmps',solverRMSE, ...
    'limits',"Synthetic electrical average-voltage bench with prescribed speed/angle. No switching inverter, FOC controller, saturation/thermal plant, paper replication or physical accuracy guarantee. FFNN corrects identification input voltage, not inverter gating.");
writeJson(fullfile(outputDirectory,'benchmark.json'),report);
save(fullfile(outputDirectory,'benchmark-data.mat'),'training','holdout','estimates','validations','network','report');
makeFigures(outputDirectory,summary,network,unseenCurrent,unseenTruth,holdout,validations);
disp(summary);
fprintf('Synthetic benchmark checks: %d/%d passed.\n',sum(structfun(@double,checks)),numel(fieldnames(checks)));
end

function record = actualVoltageRecord(record)
record.data.ud = record.data.ud_actual;
record.data.uq = record.data.uq_actual;
record.meta.voltage_input_kind = "oracle_actual_voltage_diagnostic_only";
end

function makeFigures(folder,summary,network,current,truth,holdout,validations)
figureHandle = figure('Color','w','Position',[100,100,1250,760],'Visible','off');
cleanup = onCleanup(@() close(figureHandle));
layout = tiledlayout(figureHandle,2,2,TileSpacing='compact',Padding='compact');
labels = {'Ideal','Command','Oracle','FFNN','FFNN + noise','Stale calibration'};
nexttile(layout);
bar(abs(summary{:,8:11}));
set(gca,'XTick',1:height(summary),'XTickLabel',labels,'XTickLabelRotation',20);
ylabel('Absolute parameter error (%)'); grid on;
legend('Rs','Ld','Lq','PM flux','Location','northwest');
title('Same estimator; different voltage information');
nexttile(layout);
bar(summary{:,12:13});
set(gca,'XTick',1:height(summary),'XTickLabel',labels,'XTickLabelRotation',20);
ylabel('Independent current RMSE (A)'); grid on;
legend('d axis','q axis','Location','northwest'); title('Separate excitation phase for validation');
nexttile(layout);
plot(current,truth,'k-',current,pmsm_predict_voltage_error(network,current),'b--','LineWidth',1.4);
xlabel('Phase current (A)'); ylabel('Voltage error (V)'); grid on;
legend('Synthetic unseen truth','Calibrated FFNN','Location','northwest');
title('Calibration is separate from motor parameter fitting');
nexttile(layout);
plot(holdout{4}.data.t,holdout{4}.data.iq,'k-', ...
    validations{4}.t,validations{4}.predictedCurrents(:,2),'b--','LineWidth',1.2);
xlabel('Time (s)'); ylabel('q current (A)'); grid on;
legend('Simulink holdout','Model prediction','Location','best');
title('Compensated independent prediction');
sgtitle(layout,'PMSM parameter identification — synthetic Simulink benchmark');
exportgraphics(figureHandle,fullfile(folder,'benchmark-comparison.png'),Resolution=150);
end

function writeJson(file,value)
handle = fopen(file,'w','n','UTF-8');
if handle < 0, error('pmsm:OutputFile','Cannot write benchmark JSON.'); end
cleanup = onCleanup(@() fclose(handle));
fprintf(handle,'%s',jsonencode(value,PrettyPrint=true));
end

function value = fileHash(file)
handle = fopen(file,'rb');
cleanup = onCleanup(@() fclose(handle));
digest = java.security.MessageDigest.getInstance('SHA-256');
while ~feof(handle)
    chunk = fread(handle,1048576,'*uint8');
    if ~isempty(chunk), digest.update(typecast(chunk,'int8')); end
end
bytes = typecast(digest.digest(),'uint8');
value = lower(reshape(dec2hex(bytes,2).',1,[]));
end
