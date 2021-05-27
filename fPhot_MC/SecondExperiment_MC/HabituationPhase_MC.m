function habituation

global BpodSystem %This makes the BpodSystem object visible in the protocol function's workspace

%% Setup (runs once before the first trial)
%When you launch a protocol from the launch manager, you can select a settings file.
%The settings file is simply a .mat file containing a parameter struct like the one above, which will be stored in BpodSystem.ProtocolSettings.
S = BpodSystem.ProtocolSettings;

%If the setting file is empty use these default parameters
if isempty(fieldnames(S))
    S.GUI.RewardAmount = 2;
    S.GUI.StimulusDuration= 2;
    S.GUI.MaxTrials = 30;
    S.GUI.InterTrialIntervalMean = 2;
    S.GUI.ITImin = 5;
    S.GUI.ITImax = 10;

end


% Define trial structure 
case1= 1*ones(1, S.GUI.MaxTrials/2);
case2= 2*ones(1, S.GUI.MaxTrials/2);
case0= zeros(1, 5);
TrialTypes= [case1 case2];
TrialTypes = TrialTypes(randperm(length(TrialTypes)));
TrialTypes= [TrialTypes case0];

BpodSystem.Data.TrialTypes= [];     % for storing trials completed 


ValveTime = GetValveTimes(S.GUI.RewardAmount, 1); % Return the valve-open duration in seconds for valve 1
S.inter_trial_interval= randi([S.GUI.ITImin, S.GUI.ITImax], 1, S.GUI.MaxTrials);
TotalRewardDisplay('init'); % Total Reward display (online display of the total amount of liquid reward earned)
BpodNotebook('init'); % Launches an interface to write notes about behavior and manually score trials
BpodParameterGUI('init', S); %Initialize the Parameter GUI plugin

%% Main loop (runs once per trial)
for currentTrial = 1 : S.GUI.MaxTrials
    
    % Ending sequence
    if TrialTypes(currentTrial)== 0
        disp('Session finished')
        RunProtocol('Stop');
    end
    
    
    RewardOutput= {'ValveState',1}; % open water valve    
    LoadSerialMessages('ValveModule1', {['B' 1], ['B' 2], ['B' 4], ['B' 8], ['B' 16], ['B' 32], ['B' 64], ['B' 128], ['B' 0]});
    StopStimulusOutput= {'ValveModule1', 9};   % close all the valves
    ValveTime= GetValveTimes(S.GUI.RewardAmount, 1);
    S = BpodParameterGUI('sync', S);
    
    switch TrialTypes(currentTrial)
        case 1  % Valve click - no odor 
            StateName= 'ValveOpen';
            StimulusArgument= {'ValveModule1', 2};
        case 2  % Give reward 
            StateName= 'RewardDelivery';
            StimulusArgument= {'ValveState', 1};
    end
    
    
    sma = NewStateMachine();
    sma = AddState(sma, 'Name', 'WaitForStart', ...
        'Timer', 2,...
        'StateChangeConditions', {'Tup', StateName},...
        'OutputActions', {});
    
    sma= AddState(sma, 'Name', 'ValveOpen',...
        'Timer', S.GUI.StimulusDuration,...
        'StateChangeCondition', {'Tup', 'StopStimulus'},...
        'OutputActions', StimulusArgument);
    
    sma= AddState(sma, 'Name', 'StopStimulus',...
        'Timer', 0,...
        'StateChangeCondition', {'Tup','ITI'},...
        'OutputActions', StopStimulusOutput);

    sma = AddState(sma, 'Name', 'RewardDelivery', ...
        'Timer', ValveTime,...
        'StateChangeConditions', {'Tup', 'DrinkingGrace'},...
        'OutputActions', RewardOutput);
    
    sma = AddState(sma, 'Name', 'DrinkingGrace', ...
        'Timer', 2,...
        'StateChangeConditions', {'Tup', 'ITI'},...
        'OutputActions', {});
        
    sma = AddState(sma, 'Name', 'ITI', ...
        'Timer', S.inter_trial_interval(currentTrial),...
        'StateChangeConditions', {'Tup', '>exit'},...
        'OutputActions', {});
    
    SendStateMatrix(sma); %Send the state matrix to the Bpod device
    RawEvents = RunStateMatrix; %Run the trial's finite state machine, and return the measured timecourse of events and states. The flow of states will be controlled by the Bpod device until the trial is complete (but see soft codes)
    if ~isempty(fieldnames(RawEvents)) % If trial data was returnedBpodSystem.Data = AddTrialEvents(BpodSystem.Data, RawEvents); %Add this trial's raw data to a human-readable data struct. The data struct, BpodSystem.Data, will later be saved to the current data file (automatically created based on your launch manager selections and the current time).
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
        BpodSystem.Data = BpodNotebook('sync', BpodSystem.Data); %If you are using plugins that can add data to the data struct, call their update methods.
        BpodSystem.Data.TrialSettings(currentTrial) = S; %Add a snapshot of the current settings struct, for a record of the parameters used for the current trial.
        BpodSystem.Data.TrialTypes(currentTrial) = TrialTypes(currentTrial); % Adds the trial type of the current trial to data
        UpdateTotalRewardDisplay(S.GUI.RewardAmount, currentTrial);
        SaveBpodSessionData; %Save the data struct to the current data file.
    end
    HandlePauseCondition; %If the user has pressed the "Pause" button on the Bpod console, wait here until the session is resumed
    if BpodSystem.Status.BeingUsed == 0 %If the user has ended the session from the Bpod console, exit the loop.
        clear A
        return
    end
end

function UpdateTotalRewardDisplay(RewardAmount, currentTrial)
% If rewarded based on the state data, update the TotalRewardDisplay
global BpodSystem
if ~isnan(BpodSystem.Data.RawEvents.Trial{currentTrial}.States.RewardDelivery(1))
    TotalRewardDisplay('add', RewardAmount);
end
