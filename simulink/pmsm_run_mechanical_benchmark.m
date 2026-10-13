function report = pmsm_run_mechanical_benchmark(outputDirectory)
%PMSM_RUN_MECHANICAL_BENCHMARK Staged J/B/Tc identification and failure cases.
arguments
    outputDirectory {mustBeTextScalar}
end
if isfolder(outputDirectory) || isfile(outputDirectory)
    error('pmsm:OutputExists','Choose a new mechanical benchmark folder.');
end
folder = fileparts(mfilename('fullpath'));
previousPath = path; pathCleanup = onCleanup(@() path(previousPath));
addpath(folder,fullfile(fileparts(folder),'scripts'));
temporaryRoot = getenv('PMSM_SKILL_TMPDIR');
if isempty(temporaryRoot), temporaryRoot = tempdir; end
oldFileGen = Simulink.fileGenControl('getConfig');
fileGenCleanup = onCleanup(@() Simulink.fileGenControl('setConfig','config',oldFileGen));
Simulink.fileGenControl('set','CacheFolder',fullfile(temporaryRoot,'cache'), ...
    'CodeGenFolder',fullfile(temporaryRoot,'codegen'),'createDir',true);
mkdir(outputDirectory);
bench = pmsm_mechanical_defaults();
steady = steadyRuns(bench);
friction = pmsm_identify_friction(steady.data,steady.meta);
dynamic = bench; dynamic.SpeedLoopEnabled = 0; dynamic.InitialId = 0.2;
train = pmsm_simulate_mechanical(dynamic,dynamicInputs(dynamic,0,0,0),'mechanical-train');
holdBench = dynamic; holdBench.InitialSpeed = 45;
holdout = pmsm_simulate_mechanical(holdBench,dynamicInputs(holdBench,0.8,0,0),'mechanical-holdout');
idealFit = pmsm_identify_mechanical(train.data,train.meta,friction,WindowSamples=100);
idealValidation = pmsm_validate_mechanical(idealFit,holdout.data,holdout.meta,MaxRMSE=0.1);
oldRng = rng; rng(31,'twister');
noisySteady = noisyRecord(steady,0.02,0.0001); noisySteady.meta.experiment_id = "noisy-friction";
noisyTrain = noisyRecord(train,0.02,0.0001); noisyTrain.meta.experiment_id = "noisy-train";
rng(32,'twister');
noisyHoldout = noisyRecord(holdout,0.02,0.0001); noisyHoldout.meta.experiment_id = "noisy-holdout";
rng(oldRng);
noisyFriction = pmsm_identify_friction(noisySteady.data,noisySteady.meta);
noisyFit = pmsm_identify_mechanical(noisyTrain.data,noisyTrain.meta,noisyFriction,WindowSamples=100);
noisyValidation = pmsm_validate_mechanical(noisyFit,noisyHoldout.data,noisyHoldout.meta,MaxRMSE=0.1);
loadTrain = pmsm_simulate_mechanical(dynamic,dynamicInputs(dynamic,0,0.03,0),'constant-load-train');
unknownTrain = hideLoad(loadTrain,"constant_unknown");
constantFit = pmsm_identify_mechanical(unknownTrain.data,unknownTrain.meta,friction,WindowSamples=100);
loadHoldout = pmsm_simulate_mechanical(holdBench,dynamicInputs(holdBench,0.8,-0.01,0),'known-load-holdout');
constantValidation = pmsm_validate_mechanical(constantFit,loadHoldout.data,loadHoldout.meta,MaxRMSE=0.1);
varyTrain = pmsm_simulate_mechanical(dynamic,dynamicInputs(dynamic,0,0.03,0.02),'varying-load-train');
varyHoldout = pmsm_simulate_mechanical(holdBench,dynamicInputs(holdBench,0.8,0.01,0.02),'varying-load-holdout');
knownFit = pmsm_identify_mechanical(varyTrain.data,varyTrain.meta,friction,WindowSamples=100);
knownValidation = pmsm_validate_mechanical(knownFit,varyHoldout.data,varyHoldout.meta,MaxRMSE=0.1);
wrongLoadTrain = hideLoad(varyTrain,"constant_unknown");
wrongLoadFit = pmsm_identify_mechanical(wrongLoadTrain.data,wrongLoadTrain.meta,friction,WindowSamples=100);
wrongLoadValidation = pmsm_validate_mechanical(wrongLoadFit,varyHoldout.data,varyHoldout.meta,MaxRMSE=0.1);
scaledSteady = scaleTorque(steady,1.1); scaledTrain = scaleTorque(train,1.1); scaledHoldout = scaleTorque(holdout,1.1);
scaledFriction = pmsm_identify_friction(scaledSteady.data,scaledSteady.meta);
scaledFit = pmsm_identify_mechanical(scaledTrain.data,scaledTrain.meta,scaledFriction,WindowSamples=100);
scaledValidation = pmsm_validate_mechanical(scaledFit,scaledHoldout.data,scaledHoldout.meta,MaxRMSE=0.1);
fits = {idealFit,noisyFit,constantFit,knownFit,wrongLoadFit,scaledFit};
validations = {idealValidation,noisyValidation,constantValidation,knownValidation,wrongLoadValidation,scaledValidation};
names = ["ideal","measurement_noise","constant_unknown_load","measured_varying_load","wrong_constant_load","torque_scale_plus10percent"];
parameters = zeros(numel(fits),3); errors = parameters; rmse = zeros(numel(fits),1); status = strings(numel(fits),1);
truth = [bench.J,bench.B,bench.Tc];
for k = 1:numel(fits)
    parameters(k,:) = [fits{k}.parameters.J,fits{k}.parameters.B,fits{k}.parameters.Tc];
    errors(k,:) = 100*(parameters(k,:)-truth)./truth;
    rmse(k) = validations{k}.rmseRadPerSecond; status(k) = validations{k}.status;
end
summary = table(names.',parameters(:,1),parameters(:,2),parameters(:,3),errors(:,1),errors(:,2),errors(:,3),rmse,status, ...
    VariableNames={'scenario','J_kg_m2','B_Nm_s_rad','Tc_Nm','J_error_percent','B_error_percent','Tc_error_percent','speed_rmse_rad_s','prediction_status'});
writetable(summary,fullfile(outputDirectory,'mechanical-summary.csv'));
weakBench = dynamic;
weakBench.InitialIq = (bench.B*weakBench.InitialSpeed+bench.Tc)/(1.5*bench.PolePairs*(bench.Flux+(bench.Ld-bench.Lq)*0.2));
weakTime = (0:bench.SamplePeriod:bench.StopTime).';
weakInputs = table(weakTime,zeros(size(weakTime)),weakBench.InitialIq*ones(size(weakTime)), ...
    0.2*ones(size(weakTime)),zeros(size(weakTime)), ...
    VariableNames={'t','omega_reference','iq_injection','id_reference','load_torque'});
weak = pmsm_simulate_mechanical(weakBench,weakInputs,'steady-for-J');
weakFit = pmsm_identify_mechanical(weak.data,weak.meta,friction,WindowSamples=100);
fine = dynamic; fine.SolverStep = bench.SolverStep/2;
fineRecord = pmsm_simulate_mechanical(fine,dynamicInputs(fine,0,0,0),'half-step');
halfStepRMSE = sqrt(mean((fineRecord.data.omega_m-train.data.omega_m).^2));
checks = struct('frictionRecoveryBelowPoint5Percent',all(abs(errors(1,2:3)) < 0.5), ...
    'inertiaRecoveryBelowPoint5Percent',abs(errors(1,1)) < 0.5, ...
    'independentSpeedBelowPoint1RadPerSec',rmse(1) < 0.1, ...
    'noisyParametersBelow3Percent',all(abs(errors(2,:)) < 3), ...
    'constantUnknownLoadRecoveryBelowPoint5Percent',abs(errors(3,1)) < 0.5 && abs(constantFit.parameters.trainingLoadTorque-0.03) < 0.0005, ...
    'measuredVaryingLoadRecoveryBelowPoint5Percent',abs(errors(4,1)) < 0.5, ...
    'wrongLoadAssumptionFailsPrediction',status(5) == "prediction_check_failed", ...
    'commonTorqueScaleBiasExposed',all(abs(errors(6,:)-10) < 0.5) && status(6) == "prediction_check_passed", ...
    'steadySpeedCannotIdentifyJ',weakFit.status == "not_identifiable", ...
    'halfStepDifferenceBelowPoint01RadPerSec',halfStepRMSE < 0.01);
report = struct('schemaVersion',"1.0",'kind',"synthetic_pmsm_mechanical_benchmark", ...
    'generatedAtUTC',string(datetime('now','TimeZone','UTC','Format',"yyyy-MM-dd'T'HH:mm:ss'Z'")), ...
    'matlabVersion',version,'modelSHA256',fileHash(fullfile(folder,'pmsm_mechanical_bench.slx')), ...
    'bench',bench,'cases',table2struct(summary),'checks',checks,'allChecksPassed',all(structfun(@logical,checks)), ...
    'frictionParameters',friction.parameters,'trainingConstantLoadEstimate',constantFit.parameters.trainingLoadTorque, ...
    'weakExcitationStatus',weakFit.status,'halfStepSpeedRMSEradPerSecond',halfStepRMSE, ...
    'noise',struct('speedStdRadPerSecond',0.02,'torqueStdNm',0.0001,'trainSeed',31,'holdoutSeed',32), ...
    'predictionMaxRMSEradPerSecond',0.1,'windowSamples',100, ...
    'limitations',"Synthetic reduced FOC current response, PMSM electromagnetic torque and rigid-shaft mechanics. No switching inverter, physical tests or complete 2025-paper reproduction. B/Tc fitted separately. Common torque-scale bias can pass speed prediction.");
writeJson(fullfile(outputDirectory,'mechanical-benchmark.json'),report);
save(fullfile(outputDirectory,'mechanical-records.mat'),'steady','train','holdout','fits','validations','report');
makeFigure(outputDirectory,steady,summary,holdout,idealValidation,varyHoldout,wrongLoadValidation);
disp(summary); fprintf('Mechanical benchmark: %d/%d checks passed.\n',sum(structfun(@double,checks)),numel(fieldnames(checks)));
end

function record = steadyRuns(bench)
speeds = [-80,-45,-20,20,45,80]; allData = table();
for k = 1:numel(speeds)
    setup = bench; setup.StopTime = 8; setup.InitialSpeed = 0;
    t = (0:setup.SamplePeriod:setup.StopTime).';
    inputs = table(t,speeds(k)*ones(size(t)),zeros(size(t)),zeros(size(t)),zeros(size(t)), ...
        VariableNames={'t','omega_reference','iq_injection','id_reference','load_torque'});
    record = pmsm_simulate_mechanical(setup,inputs,"friction-trial-"+k,"friction_steady");
    part = record.data(record.data.t >= 6,:);
    part.t = part.t-part.t(1)+(k-1)*2.01; part.segment = k*ones(height(part),1);
    allData = [allData;part]; %#ok<AGROW>
end
record.data = allData; record.meta.experiment_id = "friction-six-speeds";
end
function inputs = dynamicInputs(bench,phase,loadBias,loadAmplitude)
t = (0:bench.SamplePeriod:bench.StopTime).';
id_reference = 0.2*ones(size(t));
coefficient = 1.5*bench.PolePairs*(bench.Flux+(bench.Ld-bench.Lq)*0.2);
iq_injection = (0.065+loadBias+0.045*sin(2*pi*1.1*t+phase)+0.015*sin(2*pi*3.3*t+phase))/coefficient;
load_torque = loadBias+loadAmplitude*sin(2*pi*0.6*t+phase);
inputs = table(t,zeros(size(t)),iq_injection,id_reference,load_torque, ...
    VariableNames={'t','omega_reference','iq_injection','id_reference','load_torque'});
end
function record = noisyRecord(record,speedStd,torqueStd)
record.data.omega_m = record.data.omega_m+speedStd*randn(height(record.data),1);
record.data.torque_e = record.data.torque_e+torqueStd*randn(height(record.data),1);
end
function record = hideLoad(record,model)
record.data.load_torque = []; record.meta.load_model = model;
end
function record = scaleTorque(record,factor)
record.data.torque_e = factor*record.data.torque_e;
end
function makeFigure(folder,steady,summary,holdout,validation,varying,wrong)
f = figure('Color','w','Position',[100,100,1250,760],'Visible','off'); cleanup = onCleanup(@() close(f));
layout = tiledlayout(f,2,2,TileSpacing='compact',Padding='compact');
nexttile(layout); plot(steady.data.omega_m,steady.data.torque_e,'.'); grid on;
xlabel('Mechanical speed (rad/s)'); ylabel('Electromagnetic torque (N m)'); title('Six independent settled speeds');
nexttile(layout); bar(abs(summary{:,5:7})); grid on;
labels = {'Ideal','Noise','Constant load','Measured variable load','Wrong load','Torque scale +10%'};
set(gca,'XTick',1:6,'XTickLabel',labels,'XTickLabelRotation',20);
ylabel('Absolute parameter error (%)'); legend('J','B','Coulomb torque','Location','northwest'); title('Known synthetic reference parameters');
nexttile(layout); plot(holdout.data.t,holdout.data.omega_m,'k-',validation.t,validation.predictedSpeed,'b--'); grid on;
xlabel('Time (s)'); ylabel('Mechanical speed (rad/s)'); legend('Simulink','Independent prediction','Location','best'); title('Different phase and initial speed');
nexttile(layout); plot(varying.data.t,varying.data.omega_m,'k-',wrong.t,wrong.predictedSpeed,'r--'); grid on;
xlabel('Time (s)'); ylabel('Mechanical speed (rad/s)'); legend('Simulink','Wrong load assumption fit','Location','best'); title('Load changes must be represented');
sgtitle(layout,'PMSM J, viscous friction and Coulomb torque — synthetic benchmark');
exportgraphics(f,fullfile(folder,'mechanical-comparison.png'),Resolution=150);
end
function writeJson(file,value)
handle = fopen(file,'w','n','UTF-8'); if handle < 0, error('pmsm:OutputFile','Cannot write benchmark JSON.'); end
cleanup = onCleanup(@() fclose(handle)); fprintf(handle,'%s',jsonencode(value,PrettyPrint=true));
end
function value = fileHash(file)
handle = fopen(file,'rb'); if handle < 0, error('pmsm:ModelFile','Cannot read model.'); end
cleanup = onCleanup(@() fclose(handle)); digest = java.security.MessageDigest.getInstance('SHA-256');
while ~feof(handle)
    chunk = fread(handle,1048576,'*uint8');
    if ~isempty(chunk), digest.update(typecast(chunk,'int8')); end
end
bytes = typecast(digest.digest(),'uint8'); value = lower(reshape(dec2hex(bytes,2).',1,[]));
end
