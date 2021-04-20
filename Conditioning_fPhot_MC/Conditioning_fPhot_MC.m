function Conditioning_fPhot_MC

% This protocol presents the mouse with two stimuli, a rewarded odor and a non-rewarded valve click. 
% Written by Marco Colnaghi and Riccardo Tambone, 04.13.2021.
% 
% SETUP
% You will need:
% - A Bpod.
% - An Olfactometer.
% - A Lickport.

% To be presented on DAY 3 and 4.

global BpodSystem

%% Define Parameters

S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'

if isempty(fieldnames(S))             
    S.GUI.RewardAmount= 3;            % uL
    S.GUI.PreStimulusDuration= 4; 
    S.GUI.StimulusDuration= 2;
    S.GUI.PauseDuration= 1;
    S.GUI.TimeForResponseDuration= 1;
    S.GUI.DrinkingGraceDuration= 2;
    S.GUI.EndTrialLength = 4;
    S.GUI.ITImin= 17;
    S.GUI.ITImax= 23;
    S.GUI.MaxTrials= 200;
    S.GUI.mySessionTrials= 150;
end

%% Define Trial Structure

CS0Trials = [50 1];                       % Valve Click - [Number of Trials, Code]
CS1Trials_R = [95 2];                     % CS+ - [Number of Rewarded Trials, Code]
CS1Trials_nR = [5 3];                     % CS+ - [Number of non Rewarded Trials, Code]

numOfCS0    = CS0Trials(2)*ones(1, CS0Trials(1));
numOfCS1_R  = CS1Trials_R(2)*ones(1, CS1Trials_R(1));
numOfCS1_nR = CS1Trials_nR(2)*ones(1, CS1Trials_nR(1));

trialTypes = ([numOfCS0, numOfCS1_R, numOfCS1_nR]);
trialTypes = trialTypes(randperm(length(trialTypes)));               % Create Trial Vector

% Ending Sequence
endSequence = zeros(1,10);
trialTypes  = [trialTypes endSequence];                              % Add Ending Sequence

% ITI

ITI = randi([S.GUI.ITImin, S.GUI.ITImax], 1, S.GUI.mySessionTrials); % Create ITIs for each single Trial

%% Initialize Plots

TotalRewardDisplay('init'); % Total Reward display (online display of the total amount of liquid reward earned)
BpodNotebook('init'); % Launches an interface to write notes about behavior and manually score trials
BpodParameterGUI('init', S); %Initialize the Parameter GUI plugin
BpodSystem.ProtocolFigures.TrialTypeOutcomePlotFig = figure('Position', [50 440 1000 370],'name','Outcome Plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.TrialTypeOutcomePlot = axes('Position', [.075 .35 .89 .55]);
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot, 'init', trialTypes);

%% Main Loop

for currentTrial = 1: S.GUI.mySessionTrials
    LoadSerialMessages('ValveModule1', {['B' 1], ['B' 2], ['B' 4], ['B' 8], ['B' 16], ['B' 32], ['B' 64], ['B' 128], ['B' 0]});
    RewardOutput= {'ValveState',1};            % Open Water Valve
    StopStimulusOutput= {'ValveModule1', 9};   % Close all the Valves
    S = BpodParameterGUI('sync',S);
    RewardAmount = GetValveTimes(S.GUI.RewardAmount, 1);
    
    % Tial-Specific State Matrix
    switch trialTypes(currentTrial)
        
        % Valve Click
        case 1
            StimulusArgument= {'ValveModule1', 1,'BNC1', 1};        % Send TTL to DAQ (Stimulus Delivery)
            FollowingPause = 'NothingHappens';
            NothingTime = S.GUI.DrinkingGraceDuration + S.GUI.TimeForResponseDuration;
        
        % CS+ Reward
        case 2
            StimulusArgument= {'ValveModule1', 8,'BNC1', 1};        % Send TTL to DAQ (Stimulus Delivery)
            FollowingPause = 'TimeForResponse';
            LickActionState= 'Reward';                              % If Lick, Give Reward
            NoLickActionState= 'NothingHappens';                    % If not, end the Trial
            NothingTime = S.GUI.DrinkingGraceDuration;
            
        % CS+ no Reward
        case 3
            StimulusArgument= {'ValveModule1', 8,'BNC1', 1};        % Send TTL to DAQ (Stimulus Delivery)
            FollowingPause = 'NothingHappens';
            NothingTime = S.GUI.DrinkingGraceDuration + S.GUI.TimeForResponseDuration;
            
        % Exit Protocol   
        case 0
            RunProtocol('Stop');
    end
    
    % States Definitions
    
    sma= NewStateMachine(); % Initialize new state machine description
    
    sma = SetGlobalTimer(sma, 'TimerID', 1, 'Duration', 0.001, 'OnsetDelay', 0,...
                     'Channel', 'BNC2', 'OnLevel', 1, 'OffLevel', 0,...
                     'Loop', 1, 'SendGlobalTimerEvents', 0, 'LoopInterval', 0.02); 
    % Create Timer for Camera Acquisition (Set Loop Interval Properly to
    % adjust Camera Frame Rate) - 20Hz
    
    sma= AddState(sma, 'Name', 'StartTrial',...
        'Timer', 5,...
        'StateChangeCondition', {'BNC1High', 'PreStimulus'},...     % Wait for incoming TTL from Photometry System to start the Trial
        'OutputActions',{'GlobalTimerTrig', 1});                    % Starts Camera Acquisition                  
    
    sma= AddState(sma, 'Name', 'PreStimulus',...
        'Timer', S.GUI.PreStimulusDuration,...
        'StateChangeCondition', {'Tup','DeliverStimulus'},...
        'OutputActions', {});                                        

    sma= AddState(sma, 'Name', 'DeliverStimulus',...
        'Timer', S.GUI.StimulusDuration,...
        'StateChangeCondition', {'Tup','StopStimulus'},...
        'OutputActions', StimulusArgument);                         % Sends TTL to signal Stimulus Delivery Onset/Offset

    sma= AddState(sma, 'Name', 'StopStimulus',...
        'Timer', 0,...
        'StateChangeCondition', {'Tup','Pause'},...
        'OutputActions', StopStimulusOutput);
    
    sma= AddState(sma, 'Name', 'Pause',...                          % Waits for Set amount of Time (CS-ResponseWindow Delay)
        'Timer', S.GUI.PauseDuration,...
        'StateChangeCondition', {'Tup', FollowingPause},...
        'OutputActions', {});
    
    sma= AddState(sma, 'Name', 'TimeForResponse',...
        'Timer', S.GUI.TimeForResponseDuration,...
        'StateChangeCondition', {'Tup', NoLickActionState, 'Port1In', LickActionState},...
        'OutputActions', {});

    sma = AddState(sma, 'Name', 'Reward', ...                       
        'Timer', RewardAmount,...
        'StateChangeConditions', {'Tup', 'DrinkingGrace'},...
        'OutputActions', RewardOutput);

    sma = AddState(sma, 'Name', 'DrinkingGrace', ...                % Grace period for the mouse (to let him drink)
        'Timer', S.GUI.DrinkingGraceDuration,...
        'StateChangeConditions', {'Tup', 'EndTrial'},...
        'OutputActions', {});
    
    sma= AddState(sma, 'Name', 'NothingHappens',...
        'Timer', NothingTime,...
        'StateChangeCondition', {'Tup', 'EndTrial'},...
        'OutputActions', {});
    
    sma = AddState(sma, 'Name', 'EndTrial', ...
        'Timer', S.GUI.EndTrialLength,...
        'StateChangeConditions', {'Tup', 'InterTrialInterval'},...
        'OutputActions', {'GlobalTimerCancel', 1});                 % Stops Camera Acquisition
        
    sma= AddState(sma, 'Name', 'InterTrialInterval',...
        'Timer', ITI(currentTrial), ...
        'StateChangeConditions', {'Tup', '>exit'},...
        'OutputActions', {});
    
    SendStateMatrix(sma);
    RawEvents= RunStateMatrix; 
    if ~isempty(fieldnames(RawEvents)) % If trial data was returned (i.e. if not final trial, interrupted by user)
        BpodSystem.Data = AddTrialEvents(BpodSystem.Data,RawEvents); % Computes trial events from raw data
        BpodSystem.Data.TrialSettings(currentTrial) = S; % Adds the settings used for the current trial to the Data struct (to be saved after the trial ends)
        BpodSystem.Data.TrialTypes(currentTrial) = trialTypes(currentTrial); % Adds the trial type of the current trial to data
        UpdateTrialTypeOutcomePlot(trialTypes, BpodSystem.Data);
        UpdateTotalRewardDisplay(S.GUI.RewardAmount, currentTrial);
        SaveBpodSessionData; % Saves the field BpodSystem.Data to the current data file
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
        if ~isnan(Data.RawEvents.Trial{x}.States.Reward(1))
            Outcomes(x) = 1; % Licked, Reward
        else
            Outcomes(x) = -1; % No Lick
        end
        
    elseif TrialTypes(x) == 3 % CS+ no Reward Trials
        % No Graphical Display of Performance during Valve Clicks Trials (?)
        Outcomes(x) = 3; % Licked
        
    elseif TrialTypes(x) == 1 % Click Trials
        % No Graphical Display of Performance during Valve Clicks Trials (?)
        Outcomes(x) = 3; % Licked
        
    end
end
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot,'update',Data.nTrials+1,TrialTypes,Outcomes);

function UpdateTotalRewardDisplay(RewardAmount, currentTrial)
% If rewarded based on the state data, update the TotalRewardDisplay
global BpodSystem
if ~isnan(BpodSystem.Data.RawEvents.Trial{currentTrial}.States.Reward(1))
    TotalRewardDisplay('add', RewardAmount);
end
 
