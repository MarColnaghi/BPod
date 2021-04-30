function Discrimination_fPhot_MC

% This protocol presents the mouse with three stimuli, based on Hattori's(2018) paper. 
% Written by Marco Colnaghi and Riccardo Tambone, 04.20.2021.
% 
% SETUP
% You will need:
% - A Bpod.
% - An Olfactometer.
% - Three Odorants
% - A Lickport.

% To be presented on DAY 1.


global BpodSystem

%% Define Parameters

S = BpodSystem.ProtocolSettings; % Loads settings file chosen in launch manager into current workspace as a struct called 'S'

if isempty(fieldnames(S))             
    S.GUI.PreStimulusDuration= 4; 
    S.GUI.StimulusDuration= 2;
    S.GUI.PostStimulusDuration = 4;
    S.GUI.ITImin= 47;
    S.GUI.ITImax= 57;
    S.GUI.MaxTrials= 200;
    S.GUI.mySessionTrials= 50;
end

%% Define Trial Structure

stringLength = 10;                      % Number of Consecutive Trials
StructOd= [1 2 3 1 2];                    % Codes for the Odors / Define Structure
trialTypes = [];

for ii = 1:length(StructOd)
    trialTypes(:,ii) = repmat(StructOd(ii),1,stringLength);
end    

trialTypes = trialTypes(:);

% Ending Sequence
endSequence = zeros(1,20);
trialTypes  = [trialTypes' endSequence];  

% ITI

ITI = randi([S.GUI.ITImin, S.GUI.ITImax], 1, S.GUI.MaxTrials); % Create ITIs for each single Trial


%% Initialize Plots

BpodNotebook('init'); % Launches an interface to write notes about behavior and manually score trials
BpodParameterGUI('init', S); %Initialize the Parameter GUI plugin
BpodSystem.ProtocolFigures.TrialTypeOutcomePlotFig = figure('Position', [50 440 1000 370],'name','Outcome Plot','numbertitle','off', 'MenuBar', 'none', 'Resize', 'off');
BpodSystem.GUIHandles.TrialTypeOutcomePlot = axes('Position', [.075 .35 .89 .55]);
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot, 'init', trialTypes);

%% Main Loop

for currentTrial = 1: S.GUI.mySessionTrials
    LoadSerialMessages('ValveModule1', {['B' 1], ['B' 2], ['B' 4], ['B' 8], ['B' 16], ['B' 32], ['B' 64], ['B' 128], ['B' 0]});
    StopStimulusOutput= {'ValveModule1', 9};   % Close all the Valves
    S = BpodParameterGUI('sync',S);
    
    % Tial-Specific State Matrix
    switch trialTypes(currentTrial)
        
        % First Stimulus - Eugenol
        case 1
            StimulusArgument= {'ValveModule1',1,'BNC1', 1};        % Send TTL to DAQ (Stimulus Delivery)
        
        % Second Stimulus - gamma-Delactone
        case 2
            StimulusArgument= {'ValveModule1', 4,'BNC1', 1};        % Send TTL to DAQ (Stimulus Delivery)
            
        % Third Stimulus - Eucalyptol
        case 3
            StimulusArgument= {'ValveModule1', 3,'BNC1', 1};        % Send TTL to DAQ (Stimulus Delivery)

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
        'OutputActions', {'BNC2', 1});                                       % Starts Camera Acquisition                                   
    
    sma= AddState(sma, 'Name', 'DeliverStimulus',...
        'Timer', S.GUI.StimulusDuration,...
        'StateChangeCondition', {'Tup','StopStimulus'},...
        'OutputActions', StimulusArgument);                         % Sends TTL to signal Stimulus Delivery Onset/Offset

    sma= AddState(sma, 'Name', 'StopStimulus',...
        'Timer', 0,...
        'StateChangeCondition', {'Tup','PostStimulus'},...
        'OutputActions', StopStimulusOutput); 
    
    sma= AddState(sma, 'Name', 'PostStimulus',...
        'Timer', S.GUI.PostStimulusDuration,...
        'StateChangeCondition', {'Tup', 'InterTrialInterval'},...
        'OutputActions', {});                                          

    sma= AddState(sma, 'Name', 'InterTrialInterval',...
        'Timer', ITI(currentTrial), ...
        'StateChangeConditions', {'Tup', '>exit'},...
        'OutputActions', {});                                       % Stop Camera Acquisition              
    
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

Outcomes = zeros(1,Data.nTrials);
for x = 1:Data.nTrials  
    Outcomes(x) = 3; % Licked, Reward
end
TrialTypeOutcomePlot(BpodSystem.GUIHandles.TrialTypeOutcomePlot,'update',Data.nTrials+1,TrialTypes,Outcomes);


