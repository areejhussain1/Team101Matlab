% This file will Analyze all the experimental data
% 
% * look at all the data in data/
% 
% * combine (N) different trials of the same material into a [4xN] matrix
%   or a struct based on naming convention
% 
% * run plotLoadedData for each trial, extract damping ratio and other
%   important aspects
% 
% * plot damping ratio as ?bar chart? with subgroups
%       * Material + thickness
%       * Same Durometer
%       * Same Thickness

clear
clc
close all

% Settings
axisToUse = 'Az';   % 'Ax' 'Ay' 'Az'
Fs = 6400;          % sample rate (Hz)

dataDir = fullfile(pwd,'Data');
files = dir(fullfile(dataDir,'*.mat'));

results = [];   % [fileIndex  peakFreq  zeta_HP  eta_HP  zeta_log  eta_log]


summary_names = strings(0,1);
summary_zeta_log = [];
summary_eta_log  = [];
summary_zeta_hp  = [];
summary_eta_hp   = [];

currentName = "";
count = 0;

sum_zeta_log = 0;
sum_eta_log  = 0;
sum_zeta_hp  = 0;
sum_eta_hp   = 0;


% LOOP THROUGH FILES
for k = 1:numel(files)

    fileName = files(k).name;
    baseName = erase(fileName, ".mat");
    name = extractBefore(baseName, strlength(baseName) - 14);
    name = string(name);

    filePath = fullfile(dataDir,fileName);

    S = load(filePath);

    % Stack data
    data = [S.t_sec(:), S.ax_g(:), S.ay_g(:), S.az_g(:)];

    % ---- AXIS SELECTION ----
    switch upper(axisToUse)
        case 'AX'
            x = data(:,2);
        case 'AY'
            x = data(:,3);
        case 'AZ'
            x = data(:,4);
        otherwise
            error('Axis must be Ax, Ay, or Az');
    end

    [fn, zeta_HP, eta_HP, zeta_log, eta_log, delta_eta] = compute_eta_zeta_like_reference(x, Fs);


    fprintf('%s  fn=%.2f Hz  ζHP=%.4f  ζlog=%.4f  DeltaLoss%%=%.2f\n', ...
    fileName, fn, zeta_HP, zeta_log, delta_eta);


    if currentName == ""
        % First file initializes the first group
        currentName = name;
    end

    if name ~= currentName
        % Finalize previous group (average) and append as a new row
        summary_names(end+1,1)     = currentName;
        summary_zeta_log(end+1,1)  = sum_zeta_log / count;
        summary_eta_log(end+1,1)   = sum_eta_log  / count;
        summary_zeta_hp(end+1,1)   = sum_zeta_hp  / count;
        summary_eta_hp(end+1,1)    = sum_eta_hp   / count;

        % Reset accumulators for the new group
        currentName = name;
        count = 0;
        sum_zeta_log = 0; sum_eta_log = 0; sum_zeta_hp = 0; sum_eta_hp = 0;
    end


    sum_zeta_log = sum_zeta_log + zeta_log;
    sum_eta_log  = sum_eta_log  + eta_log;
    sum_zeta_hp  = sum_zeta_hp  + zeta_HP;
    sum_eta_hp   = sum_eta_hp   + eta_HP;


    count = count + 1;
end


if currentName ~= "" && count > 0
    summary_names(end+1,1)     = currentName;
    summary_zeta_log(end+1,1)  = sum_zeta_log / count;
    summary_eta_log(end+1,1)   = sum_eta_log  / count;
    summary_zeta_hp(end+1,1)   = sum_zeta_hp  / count;
    summary_eta_hp(end+1,1)    = sum_eta_hp   / count;
end

avgTable = table( ...
    summary_names, summary_zeta_log, summary_eta_log, summary_zeta_hp, summary_eta_hp, ...
    'VariableNames', {'name','zeta_log','eta_log','zeta_hp','eta_hp'} );

disp('===== AVERAGES PER NAME =====');
disp(avgTable);




function [peak_f, zeta_hp, eta_hp, zeta_log, eta_log, delta_eta] = compute_eta_zeta_like_reference(x, Fs)
    % Make x column
    x = x(:);
    N = numel(x);
    if N < 2
        peak_f = NaN; zeta_hp = NaN; eta_hp = NaN; zeta_log = NaN; eta_log = NaN; delta_eta = NaN;
        return;
    end

    % --- Reconstruct uniform time vector (reference does this) ---
    t_sec = (0:N-1).' / Fs;

    % --- Remove DC offset (reference uses x_detrend) ---
    x_detrend = x - mean(x);

    %% ==========================
    %  HALF-POWER METHOD (FFT)
    %  ==========================
    w  = hann(N);
    xw = x_detrend .* w;

    X  = fft(xw);

    % Reference scaling: P2 = abs(X)/N, then single-sided with doubling
    P2 = abs(X) / N;                    % two-sided
    P1 = P2(1:floor(N/2)+1);            % single-sided
    if numel(P1) > 2
        P1(2:end-1) = 2*P1(2:end-1);
    end

    f = Fs*(0:floor(N/2))/N;

    [max_mag, i_peak] = max(P1);
    peak_f = f(i_peak);

    hp_mag = max_mag / sqrt(2);

    % Reference half-power crossing selection
    % NOTE: left uses hp_mag*0.95 in the reference
    [~, i_left] = min(abs(P1(1:i_peak) - hp_mag*0.95));
    f1 = f(i_left);

    [~, i_right_rel] = min(abs(P1(i_peak:end) - hp_mag));
    i_right = i_peak + i_right_rel - 1;
    f2 = f(i_right);

    df = f2 - f1;
    eta_hp  = df / peak_f;
    zeta_hp = df / (2*peak_f);

    %% ==========================
    %  LOGARITHMIC DECREMENT (time domain)
    %  ==========================
    % Reference uses signed peaks on x_detrend, not abs envelope

    if peak_f <= 0 || isnan(peak_f)
        zeta_log = NaN; eta_log = NaN;
    else
        % Estimate period from peak frequency
        Tn = 1 / peak_f;

        % Peak detection: enforce min spacing
        minPeakDist_sec = 0.5 * Tn;
        [x_peaks, locs] = findpeaks(x_detrend, t_sec, 'MinPeakDistance', minPeakDist_sec);

        if numel(x_peaks) < 3
            zeta_log = NaN; eta_log = NaN;
        else
            % --- Handle clipping at the start (reference logic) ---
            clip_level = max(abs(x_detrend));
            tol = 1e-3 * clip_level;

            clip_idx = find(abs(x_detrend) >= clip_level - tol);
            if ~isempty(clip_idx)
                t_clip_end = t_sec(clip_idx(end));
                keep_clip  = locs > t_clip_end;
                x_peaks_u  = x_peaks(keep_clip);
                locs_u     = locs(keep_clip);
            else
                x_peaks_u = x_peaks;
                locs_u    = locs;
            end

            % --- 1) Apply magnitude threshold (reference uses 5 g in your pasted code) ---
            A_mag = abs(x_peaks_u);
            keep_big = A_mag >= 5;
            A1 = A_mag(keep_big);

            if numel(A1) < 2
                zeta_log = NaN; eta_log = NaN;
            else
                % --- 2) Remove neighbor-outlier peaks (reference alpha=0.8) ---
                alpha = 0.8;
                keep_neighbor = true(size(A1));

                if numel(A1) >= 3
                    for k = 2:numel(A1)-1
                        neighbor_min = min(A1(k-1), A1(k+1));
                        if A1(k) < alpha * neighbor_min
                            keep_neighbor(k) = false;
                        end
                    end
                end

                A = A1(keep_neighbor);

                if numel(A) < 2
                    zeta_log = NaN; eta_log = NaN;
                else
                    deltas = log(A(1:end-1) ./ A(2:end));
                    delta_bar = mean(deltas);

                    zeta_log = delta_bar / sqrt(4*pi^2 + delta_bar^2);
                    eta_log  = 2 * zeta_log;
                end
            end
        end
    end

    %% ==========================
    %  ERROR CALC (reference)
    %  ==========================
    % reference: delta_eta = abs(eta_hp - eta_log)/eta_log * 100;
    if isnan(eta_log) || eta_log == 0
        delta_eta = NaN;
    else
        delta_eta = abs(eta_hp - eta_log) / eta_log * 100;
    end
end
