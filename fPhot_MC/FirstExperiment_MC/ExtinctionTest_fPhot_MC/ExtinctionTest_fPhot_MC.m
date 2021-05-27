function ExtinctionTest_fPhot_MC

% This protocol presents the mouse with three stimuli, a rewarded odor and a non-rewarded valve click. 
% Written by Marco Colnaghi and Riccardo Tambone, 04.18.2021.
% 
% SETUP
% You will need:
% - A Bpod.
% - An Olfactometer.
% - A Lickport.

% To be presented on DAY 5 before 'Conditioning_fPhot_MC.
global BpodSystem

%% Define Parameters

S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'

if isempty(fieldnames(S))             
    S.GUI.PreStimulusDuration= 4; 
    S.GUI.StimulusDuration= 2;
    S.GUI.PauseDuration= 1;
    S.GUI.TimeForResponseDuration= 1;
    S.GUI.DrinkingGraceDuration= 2;
    S.GUI.EndTrialLength = 4;
    S.GUI.ITImin= 5;
    S.GUI.ITImax= 8;
    S.GUI.MaxTrials= 50;
    S.GUI.mySessionTrials= 10;
end

%% Define Trial Structure

numOfTrials = 5;

numOfCS1 = 2*ones(1, numOfTrials);
numOfCS2 = 4*ones(1, numOfTrials);

trialTypes = ([numOfCS1, numOfCS2]);
trialTypes = trialTypes(randperm(length(trialTypes)));               % Create Trial Vector

% Ending Sequence
endSequence = zeros(1,40);
trialTypes  = [trialTypes endSequence];                              % Add Ending Sequence

% ITI

ITI = randi([S.GUI.ITImin, S.GUI.ITImax], 1, S.GUI.MaxTrials); % Create ITIs for each single Trial

%% Initialize Plots

BpodNotebook('init'); % Launches an interface to write notes about behavior and manually score trials
BpodParameterGUI('init', S); %Initialize the Parameter GUI plugin
BpodSystem.ProtocolFigures.TrialTypeOutcomePlotFig = figure('Position', [50 440 1000 370],'name','Outcome Plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.TrialTypeOutcomePlot = axes('Position', [.075 .35 .89 .55]);
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot, 'init', trialTypes);

%% Main Loop

for currentTrial = 1: S.GUI.MaxTrials
    LoadSerialMessages('ValveModule1', {['B' 1], ['B' 2], ['B' 4], ['B' 8], ['B' 16], ['B' 32], ['B' 64], ['B' 128], ['B' 0]});
    StopStimulusOutput= {'ValveModule1', 9};   % Close all the Valves
    S = BpodParameterGUI('sync',S);
    
    % Tial-Specific State Matrix
    switch trialTypes(currentTrial)
        
       % CS1+ Reward
        case 2
            StimulusArgument= {'ValveModule1', 5,'BNC1', 1};        % Send TTL to DAQ (Stimulus Delivery)
            FollowingPause = 'NothingHappens';
            NothingTime = S.GUI.DrinkingGraceDuration + S.GUI.TimeForResponseDuration;
            
            % CS2-
        case 5
            StimulusArgument= {'ValveModule1', 6,'BNC1', 1};        % Send TTL to DAQ (Stimulus Delivery)
            FollowingPause = 'NothingHappens';                      % End the Trial
            NothingTime = S.GUI.DrinkingGraceDuration + S.GUI.TimeForResponseDuration;
            
            % Exit Protocol
        case 0
            RunProtocol('Stop');

    end
    
    % States Definitions
    
    sma= NewStateMachine(); % Initialize new state machine description
    
    sma= AddState(sma, 'Name', 'StartTrial',...
        'Timer', 10,...
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
    
    sma= AddState(sma, 'Name', 'TimeForResponse',...
        'Timer', S.GUI.TimeForResponseDuration,...
        'StateChangeCondition', {'Tup', 'NothingHappens'},...
        'OutputActions', {});
    
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

Outcomes = nan(1,Data.nTrials);
for x = 1:Data.nTrials
    if TrialTypes(x) == 2 % CS+ Trials
        Outcomes(x) = 3;
        
    elseif TrialTypes(x) == 4 % CS- Trials
        % No Graphical Display of Performance during Valve Clicks Trials (?)
        Outcomes(x) = 3;
    end
    
end
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot,'update',Data.nTrials+1,TrialTypes,Outcomes);
