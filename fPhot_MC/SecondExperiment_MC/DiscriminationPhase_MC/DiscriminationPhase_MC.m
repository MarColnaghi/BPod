function Discriminationhase_MC

% This protocol presents the mouse with two stimuli, a rewarded odor and a non-rewarded valve click. 
% Written by Marco Colnaghi and Riccardo Tambone, 04.13.2021.
% 
% SETUP
% You will need:
% - A Bpod.
% - An Olfactometer.
% - A Lickport.

% To be presented on DAY 5, 6, 7 and 8.

global BpodSystem

%% Setup (runs once before the first trial)

%When you launch a protocol from the launch manager, you can select a settings file.
%The settings file is simply a .mat file containing a parameter struct like the one above, which will be stored in BpodSystem.ProtocolSettings.
S = BpodSystem.ProtocolSettings;

if isempty(fieldnames(S))             
    S.GUI.RewardAmount= 3;            % uL
    S.GUI.PreStimulusDuration= 5;     
    S.GUI.StimulusDuration= 2;
    S.GUI.PauseDuration= 3;
    S.GUI.LEDDuration= 1;
    S.GUI.DrinkingGraceDuration= 2;
    S.GUI.EndTrialLength = 4;
    S.GUI.ITImin= 5;
    S.GUI.ITImax= 8;
    S.GUI.MaxTrials= 200;
    S.GUI.mySessionTrials= 150;
end

%% Define Trial Structure

CS0Trials = [75 1];                       % Valve Click - [Number of Trials, Code]
CS1Trials_R = [71 2];                     % CS+ - [Number of Rewarded Trials, Code]
CS1Trials_nR = [4 3];                     % CS+ - [Number of non Rewarded Trials, Code]

numOfCS0    = CS0Trials(2)*ones(1, CS0Trials(1));
numOfCS1_R  = CS1Trials_R(2)*ones(1, CS1Trials_R(1));
numOfCS1_nR = CS1Trials_nR(2)*ones(1, CS1Trials_nR(1));

trialTypes = ([numOfCS0, numOfCS1_R, numOfCS1_nR]);
trialTypes = trialTypes(randperm(length(trialTypes)));               % Create Trial Vector

% Ending Sequence
endSequence = zeros(1,50);
trialTypes  = [trialTypes endSequence];                              % Add Ending Sequence

% ITI
ITI = randi([S.GUI.ITImin, S.GUI.ITImax], 1, S.GUI.MaxTrials); % Create ITIs for each single Trial

%% Initialize Plots

TotalRewardDisplay('init'); % Total Reward display (online display of the total amount of liquid reward earned)
BpodNotebook('init'); % Launches an interface to write notes about behavior and manually score trials
BpodParameterGUI('init', S); %Initialize the Parameter GUI plugin
BpodSystem.ProtocolFigures.TrialTypeOutcomePlotFig = figure('Position', [50 440 1000 370],'name','Outcome Plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.TrialTypeOutcomePlot = axes('Position', [.075 .35 .89 .55]);
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot, 'init', trialTypes);

%% Main Loop

for currentTrial = 1: S.GUI.MaxTrials
    
    LoadSerialMessages('ValveModule1', {['B' 1], ['B' 2], ['B' 4], ['B' 8], ['B' 16], ['B' 32], ['B' 64], ['B' 128], ['B' 0]});
    RewardOutput= {'ValveState',1, 'BNC1', 1}; % Open Water Valve
    StopStimulusOutput= {'ValveModule1', 9};   % Close all the Valves
    S = BpodParameterGUI('sync',S);
    RewardAmount = GetValveTimes(S.GUI.RewardAmount, 1);
    LEDon= {'PWM1',255};
    S = BpodParameterGUI('sync',S);
    
    % Tial-Specific State Matrix
    switch trialTypes(currentTrial)
        
        % Carvone
        case 1 
            StimulusArgument= {'ValveModule1', 6, 'BNC1',1};        % Insert the number of the valve to be opened WITHOUT odor
            FollowingLED = 'FakeReward';
            EndTrialDuration= S.GUI.EndTrialLength + S.GUI.DrinkingGraceDuration;
        
        % CS+ Reward
        case 2
            StimulusArgument= {'ValveModule1', 7, 'BNC1',1};        % Inser the number of the valve to be opened for odors 
            FollowingLED = 'Reward';
            EndTrialDuration= S.GUI.EndTrialLength;
         
        % CS+ no Reward
        case 3
            StimulusArgument= {'ValveModule1', 7, 'BNC1',1};        % Insert the number of the valve to be opened for odors
            FollowingLED = 'FakeReward';
            EndTrialDuration= S.GUI.EndTrialLength + S.GUI.DrinkingGraceDuration;
            
        % Exit Protocol   
        case 0
            RunProtocol('Stop');
            
    end
        
            
    sma= NewStateMachine(); % Initialize new state machine description    
    
    sma= AddState(sma, 'Name', 'StartTrial',...
        'Timer', 10,...
        'StateChangeCondition', {'BNC1High', 'PreStimulus'},...     % Wait for incoming TTL from Photometry System to start the Trial
        'OutputActions',{});
    
    sma= AddState(sma, 'Name', 'PreStimulus',...
        'Timer', S.GUI.PreStimulusDuration,...
        'StateChangeCondition', {'Tup','DeliverStimulus'},...
        'OutputActions', {'BNC2', 1});
    
    sma= AddState(sma, 'Name', 'DeliverStimulus',...
        'Timer', S.GUI.StimulusDuration,...
        'StateChangeCondition', {'Tup','StopStimulus'},...
        'OutputActions', StimulusArgument);                        

    sma= AddState(sma, 'Name', 'StopStimulus',...
        'Timer', 0,...
        'StateChangeCondition', {'Tup','Pause'},...
        'OutputActions', StopStimulusOutput);
    
    sma= AddState(sma, 'Name', 'Pause',...                          % Waits for Set amount of Time (CS-ResponseWindow Delay)
        'Timer', S.GUI.PauseDuration,...
        'StateChangeCondition', {'Tup', 'LEDon'},...
        'OutputActions', {});
    
    sma= AddState(sma, 'Name', 'LEDon',...
        'Timer', S.GUI.LEDDuration,...
        'StateChangeCondition', {'Tup', FollowingLED},...
        'OutputActions', LEDon);

    sma = AddState(sma, 'Name', 'Reward', ...                       
        'Timer', RewardAmount,...
        'StateChangeConditions', {'Tup', 'DrinkingGrace'},...
        'OutputActions', RewardOutput);

    sma = AddState(sma, 'Name', 'DrinkingGrace', ...                % Grace period for the mouse (to let him drink)
        'Timer', S.GUI.DrinkingGraceDuration,...
        'StateChangeConditions', {'Tup', 'EndTrial'},...
        'OutputActions', {});
    
    sma= AddState(sma, 'Name', 'FakeReward', ...
        'Timer', RewardAmount, ...
        'StateChangeConditions', {'Tup', 'EndTrial'},...
        'OutputActions', {});
        
    sma = AddState(sma, 'Name', 'EndTrial', ...
        'Timer', EndTrialDuration,...
        'StateChangeConditions', {'Tup', 'InterTrialInterval'},...
        'OutputActions', {});
    
    sma= AddState(sma, 'Name', 'InterTrialInterval',...
        'Timer', ITI(currentTrial), ...
        'StateChangeConditions', {'Tup', '>exit'},...
        'OutputActions', {});                 
    
    SendStateMatrix(sma);
    RawEvents= RunStateMatrix;
    if ~isempty(fieldnames(RawEvents)) % If trial data was returned (i.e. if not final trial, interrupted by user)
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
        BpodSystem.Data = BpodNotebook('sync', BpodSystem.Data); %If you are using plugins that can add data to the data struct, call their update methods.
        BpodSystem.Data.TrialSettings(currentTrial) = S; %Add a snapshot of the current settings struct, for a record of the parameters used for the current trial.
        BpodSystem.Data.TrialTypes(currentTrial) = trialTypes(currentTrial); % Adds the trial type of the current trial to data
        UpdateTotalRewardDisplay(S.GUI.RewardAmount, currentTrial);
        UpdateTrialTypeOutcomePlot(trialTypes, BpodSystem.Data);
        SaveBpodSessionData; %Save the data struct to the current data file.
    end
    HandlePauseCondition;
    if BpodSystem.Status.BeingUsed == 0
        Obj= ValveDriverModule('COM7');   %%%
        for idx= 1:8
            closeValve(Obj, idx)
        end
        return;
    end
end


% -1: error, unpunished (unfilled red circle)
% 0: error, punished (filled red circle)
% 1: correct, rewarded (filled green circle)
% 2: correct, unrewarded (unfilled green circle)
% 3: no response (unfilled black circle)

function UpdateTrialTypeOutcomePlot(TrialTypes, Data)
% Determine outcomes from state data and score as the SideOutcomePlot plugin expects

global BpodSystem

Outcomes = zeros(1,Data.nTrials);
for x = 1:Data.nTrials
    if TrialTypes(x) == 2 % CS+ Trials
        if ~isfield(Data.RawEvents.Trial{x}.Events,'Port1In')
            Outcomes(x) = -1; % No Lick
        else
            licks_ts= Data.RawEvents.Trial{x}.Events.Port1In;
            infBound= Data.RawEvents.Trial{x}.States.LEDon(1);
            supBound= Data.RawEvents.Trial{x}.States.LEDon(2);
            if any(licks_ts> infBound) && any(licks_ts< supBound)
                Outcomes(x) = 1; % Lick
            else
                Outcomes(x)= -1; % No Lick, wrong
            end
        end
    elseif TrialTypes(x) == 1 % No Odor Trials
        if ~isfield(Data.RawEvents.Trial{x}.Events,'Port1In')
            Outcomes(x) = 1; % No Lick, correct
        else
            licks_ts= Data.RawEvents.Trial{x}.Events.Port1In;
            infBound= Data.RawEvents.Trial{x}.States.LEDon(1);
            supBound= Data.RawEvents.Trial{x}.States.LEDon(2);
            if any(licks_ts> infBound) && any(licks_ts< supBound)
                Outcomes(x) = -1; % Lick, wrong
            else
                Outcomes(x)= 1; % No Lick
            end
        end
    elseif TrialTypes(x) == 1 % No Odor Trials
        Outcomes(x) = 3; % No Lick, correct
    end
end
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot,'update',Data.nTrials+1,TrialTypes,Outcomes);

function UpdateTotalRewardDisplay(RewardAmount, currentTrial)
% If rewarded based on the state data, update the TotalRewardDisplay
global BpodSystem
if ~isnan(BpodSystem.Data.RawEvents.Trial{currentTrial}.States.Reward(1))
    TotalRewardDisplay('add', RewardAmount);
end

