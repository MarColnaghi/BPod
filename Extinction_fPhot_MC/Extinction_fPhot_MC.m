function Extinction_fPhot_MC

% This protocol presents the mouse with two stimuli, a rewarded odor, a non-rewarded odor and a punishing odor.
% Written by Marco Colnaghi and Riccardo Tambone, 04.14.2021.
% 
% SETUP
% You will need:
% - A Bpod.
% - An Olfactometer.
% - Three Odorants
% - A Lickport.
% - An Air Puff System

% To be presented on DAY 7 and 8.

global BpodSystem

%% Define Parameters

S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'

if isempty(fieldnames(S))             
    S.GUI.RewardAmount= 3;            % uL
    S.GUI.PreStimulusDuration= 4; 
    S.GUI.StimulusDuration= 2;
    S.GUI.PauseDuration= 1;
    S.GUI.AirPuffTime= 2;
    S.GUI.NothingTime = 2;
    S.GUI.EndTrialLength= 4;
    S.GUI.ITImin= 17;
    S.GUI.ITImax= 23;
    S.GUI.MaxTrials= 200;
    S.GUI.mySessionTrials= 80;
end

%% Define Trial Structure

numOfTrials = 40;

numOfCS1 = 2*ones(1, numOfTrials);
numOfCS3 = 5*ones(1, numOfTrials);

trialTypes = ([numOfCS1 numOfCS3]); 
trialTypes = trialTypes(randperm(length(trialTypes))); 

% Ending Sequence
endSequence = zeros(1,10);
trialTypes  = [trialTypes endSequence]; 

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

for currentTrial = 1: S.GUI.mySessionTrials
    LoadSerialMessages('ValveModule1', {['B' 1], ['B' 2], ['B' 4], ['B' 8], ['B' 16], ['B' 32], ['B' 64], ['B' 128], ['B' 0]});
    RewardOutput= {'ValveState',1};            % Open Water Valve
    StopStimulusOutput= {'ValveModule1', 9};   % Close all the Valves
    S = BpodParameterGUI('sync',S);
    RewardAmount = GetValveTimes(S.GUI.RewardAmount, 1);
    AirPuff =  {'ValveModule1', 2, 'BNC1', 1};            % Valve for AirPuff Punishment
    
    % Tial-Specific State Matrix
    switch trialTypes(currentTrial)
        
        % CS1+
        case 2
            StimulusArgument= {'ValveModule1', 8,'BNC1', 1};
            FollowingPause= 'NothingHappens';
            
        % CS3 w/ Punishment
        case 5
            StimulusArgument= {'ValveModule1', 6,'BNC1', 1};
            FollowingPause= 'Air Puff';   
    end
    
    % States Definitions   
    
    
    sma= NewStateMachine(); % Initialize new state machine description    
    
    sma= AddState(sma, 'Name', 'StartTrial',...
        'Timer', 5,...
        'StateChangeCondition', {'BNC1High', 'PreStimulus'},...     % Wait for incoming TTL from Photometry System to start the Trial
        'OutputActions',{});                                        
    
    sma= AddState(sma, 'Name', 'PreStimulus',...
        'Timer', S.GUI.PreStimulusDuration,...
        'StateChangeCondition', {'Tup','DeliverStimulus'},...
        'OutputActions', {'BNC2', 1});                              % Starts Camera Acquisition          

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
    
    sma = AddState(sma, 'Name', 'AirPuff', ...
        'Timer', S.GUI.AirPuffTime,...
        'StateChangeConditions', {'Tup', 'EndTrial'},...
        'OutputActions', AirPuff);
    
    sma= AddState(sma, 'Name', 'NothingHappens',...
        'Timer', NothingTime,...
        'StateChangeCondition', {'Tup', 'EndTrial'},...
        'OutputActions', {});
    
    sma = AddState(sma, 'Name', 'EndTrial', ...
        'Timer', S.GUI.EndTrialLength,...
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


% -1: error, continues to lick (unfilled red circle)
% 1: correct, didn't lick (filled green circle)
% 3: punishment (unfilled black circle)

function UpdateTrialTypeOutcomePlot(TrialTypes, Data)
% Determine outcomes from state data and score as the SideOutcomePlot plugin expects

global BpodSystem

Outcomes = nan(1,Data.nTrials);
for x = 1:Data.nTrials
    if TrialTypes(x) == 2 % CS+ Trials
        Outcomes(x) = 3;
        
    elseif TrialTypes(x) == 6 % Punishment Trials
        Outcomes(x) = 3;
    end
end
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot,'update',Data.nTrials+1,TrialTypes,Outcomes);

function UpdateTotalRewardDisplay(RewardAmount, currentTrial)
% If rewarded based on the state data, update the TotalRewardDisplay
global BpodSystem
if ~isnan(BpodSystem.Data.RawEvents.Trial{currentTrial}.States.Reward(1))
    TotalRewardDisplay('add', RewardAmount);
end
 

