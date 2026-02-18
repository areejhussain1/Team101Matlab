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
% * produce an avg table per material name (grouped by naming convention)
% * ALSO store every individual trial in a struct array "tests" (Option A)

clear
clc
close all

% Settings
axisToUse = 'Az';   % 'Ax' 'Ay' 'Az'
Fs = 6400;          % sample rate (Hz)

dataDir = fullfile(pwd,'Data');
files = dir(fullfile(dataDir,'*.mat'));


R = struct();   % results grouped by name

summary_names = strings(0,1);
summary_zeta_log = [];
summary_eta_log  = [];
summary_zeta_hp  = [];
summary_eta_hp   = [];
summary_zeta = [];
summary_eta = [];

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

    key = matlab.lang.makeValidName(name);   % sanitize for fieldname (e.g. "rub", "SCPOLY")

% Initialize this name bucket once
if ~isfield(R, key)
    R.(key).file       = strings(0,1);
    R.(key).fn         = [];
    R.(key).zeta_HP    = [];
    R.(key).eta_HP     = [];
    R.(key).zeta_log   = [];
    R.(key).eta_log    = [];
    R.(key).delta_eta  = [];
end

% Append one row/entry for this file
R.(key).file(end+1,1)      = string(fileName);
R.(key).fn(end+1,1)        = fn;
R.(key).zeta_HP(end+1,1)   = zeta_HP;
R.(key).eta_HP(end+1,1)    = eta_HP;
R.(key).zeta_log(end+1,1)  = zeta_log;
R.(key).eta_log(end+1,1)   = eta_log;
R.(key).delta_eta(end+1,1) = delta_eta;


    fprintf('%s  fn=%.2f Hz  ζHP=%.4f  ζlog=%.4f ηHP=%.4f ηlog=%.4f DeltaLoss%%=%.2f\n', ...
    fileName, fn, zeta_HP, zeta_log,eta_HP, eta_log, delta_eta);


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
        summary_zeta(end+1, 1) = ((sum_zeta_log / count)+(sum_zeta_hp  / count))/2;
        summary_eta(end+1, 1) = ((sum_eta_log / count)+(sum_eta_hp  / count))/2;

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
    summary_zeta(end+1, 1) = ((sum_zeta_log / count)+(sum_zeta_hp  / count))/2;
    summary_eta(end+1, 1) = ((sum_eta_log / count)+(sum_eta_hp  / count))/2;
end

%avgTable = table( ...
%    summary_names, summary_zeta_log, summary_eta_log, summary_zeta_hp, summary_eta_hp, summary_zeta, summary_eta, ...
%    'VariableNames', {'name','zeta_log','eta_log','zeta_hp','eta_hp',
%    'zeta', 'eta'} );%
%disp(avgTable);

keys = string(fieldnames(R));
nG = numel(keys);

summary_names = strings(nG,1);
summary_zeta_log = nan(nG,1);
summary_eta_log  = nan(nG,1);
summary_zeta_hp  = nan(nG,1);
summary_eta_hp   = nan(nG,1);
summary_zeta     = nan(nG,1);
summary_eta      = nan(nG,1);

for i = 1:nG
    k = keys(i);
    summary_names(i)    = k;

    summary_zeta_log(i) = mean(R.(k).zeta_log, 'omitnan');
    summary_eta_log(i)  = mean(R.(k).eta_log,  'omitnan');
    summary_zeta_hp(i)  = mean(R.(k).zeta_HP,  'omitnan');
    summary_eta_hp(i)   = mean(R.(k).eta_HP,   'omitnan');

    summary_zeta(i) = mean([summary_zeta_log(i), summary_zeta_hp(i)], 'omitnan');
    summary_eta(i)  = mean([summary_eta_log(i),  summary_eta_hp(i)],  'omitnan');
end

avgTable = table( ...
    summary_names, summary_zeta_log, summary_eta_log, summary_zeta_hp, summary_eta_hp, summary_zeta, summary_eta, ...
    'VariableNames', {'name','zeta_log','eta_log','zeta_hp','eta_hp','zeta','eta'} );

disp(avgTable);

keys = string(fieldnames(R));
G = numel(keys);

name_out = strings(G,1);

hp_n  = zeros(G,1);  hp_mu  = nan(G,1);  hp_lo  = nan(G,1);  hp_hi  = nan(G,1);
log_n = zeros(G,1);  log_mu = nan(G,1);  log_lo = nan(G,1);  log_hi = nan(G,1);
avg_n = zeros(G,1);  avg_mu = nan(G,1);  avg_lo = nan(G,1);  avg_hi = nan(G,1);

for i = 1:G
    key = keys(i);
    name_out(i) = key;

    zhp  = R.(key).zeta_HP(:);
    zlog = R.(key).zeta_log(:);

    % Per-sample average of the two (robust to NaNs)
    zavg = mean([zhp, zlog], 2, 'omitnan');

    [hp_mu(i),  hp_lo(i),  hp_hi(i),  hp_n(i)]  = mean_ci95(zhp);
    [log_mu(i), log_lo(i), log_hi(i), log_n(i)] = mean_ci95(zlog);
    [avg_mu(i), avg_lo(i), avg_hi(i), avg_n(i)] = mean_ci95(zavg);
end

statsTable = table( ...
    name_out, ...
      hp_mu,  hp_lo,  hp_hi, ...
     log_mu, log_lo, log_hi, ...
     avg_n, avg_mu, avg_lo, avg_hi, (avg_hi-avg_lo), ...
    'VariableNames', { ...
      'name', ...
      'zeta_hp_mean','zeta_hp_ci_lo','zeta_hp_ci_hi', ...
      'zeta_log_mean','zeta_log_ci_lo','zeta_log_ci_hi', ...
      'avg_n','zeta_avg_mean','zeta_avg_ci_lo','zeta_avg_ci_hi','zeta_avg_ci_width' } );
%% 

disp(statsTable);

%
% PLOTTING EACH MATERIAL ON SUBPLOT, ERROR BARS FOR THE C.I. FOR THE MEAN
%

% --- Sort materials by AVG mean (highest to lowest) ---
statsTable = sortrows(statsTable, 'zeta_avg_mean', 'descend');

keys_sorted = string(statsTable.name);
G = numel(keys_sorted);

% --- Choose subplot grid ---
nCols = ceil(sqrt(G));
nRows = ceil(G / nCols);

figure('Name','Per-material ζ (HP/LOG/AVG) distributions + mean±95%CI');
t = tiledlayout(nRows, nCols, 'TileSpacing','compact', 'Padding','compact');

for i = 1:G
    key = keys_sorted(i);

    % Distributions from struct
    zhp  = R.(key).zeta_HP(:);
    zlog = R.(key).zeta_log(:);
    zavg = mean([zhp, zlog], 2, 'omitnan');   % per-sample average

    % Precomputed mean/CI from statsTable (no recompute)
    row = statsTable(i, :);
    mus = [row.zeta_hp_mean,  row.zeta_log_mean,  row.zeta_avg_mean];
    los = [row.zeta_hp_ci_lo, row.zeta_log_ci_lo, row.zeta_avg_ci_lo];
    his = [row.zeta_hp_ci_hi, row.zeta_log_ci_hi, row.zeta_avg_ci_hi];

    nexttile;
    hold on; grid on;

    % ---- Numeric grouping (robust; avoids categorical xticks issues) ----
    vals = [zhp; zlog; zavg];
    g    = [ones(numel(zhp),1); 2*ones(numel(zlog),1); 3*ones(numel(zavg),1)];

        boxchart(g, vals);
  

    set(gca, 'XTick', 1:3, 'XTickLabel', {'HP','LOG','AVG'});

    % Overlay mean ± 95% CI
    x = 1:3;
    errorbar(x, mus, mus-los, his-mus, 'r', ...
        'LineStyle','none', 'LineWidth',1.3, 'CapSize',10);
    plot(x, mus, 'kd', 'MarkerFaceColor','r', 'MarkerSize',6);

    ylabel('\zeta');
    title(sprintf('%s | AVG=%.4f', key, row.zeta_avg_mean), 'Interpreter','none');

    hold off;
end

title(t, 'Per material: distribution (box plot in blue & black) + mean \pm 95% CI in red');

%
% PLOTTING ALL THE MATERIALS AVG ON ONE
%

figure('Name','All materials: AVG mean ± 95% CI (sorted)');
hold on; grid on;

x  = 1:height(statsTable);
mu = statsTable.zeta_avg_mean;
lo = statsTable.zeta_avg_ci_lo;
hi = statsTable.zeta_avg_ci_hi;

% Create a set of distinct colors (one per material)
N = numel(x);
block = 7;  % switch palette every 7

palettes = {@lines, @parula, @turbo, @hsv, @spring, @summer, @autumn, @winter, @cool, @hot, @copper};

cols = zeros(N,3);
idx = 1;
p = 1;

while idx <= N
    m = min(block, N - idx + 1);          % how many colors we still need in this block
    cmap = palettes{p}(max(block, m));     % generate at least 'block' colors for consistent look
    cols(idx:idx+m-1, :) = cmap(1:m, :);   % take first m colors
    idx = idx + m;
    p = p + 1;
    if p > numel(palettes)
        p = 1; % wrap if you have tons of materials
    end
end


h = gobjects(numel(x),1);

for i = 1:numel(x)
    h(i) = errorbar(x(i), mu(i), mu(i)-lo(i), hi(i)-mu(i), 'o', ...
        'LineStyle','none', 'LineWidth',1.5, 'CapSize',10, ...
        'MarkerFaceColor', cols(i,:), 'MarkerEdgeColor', cols(i,:), ...
        'Color', cols(i,:));   % sets the vertical CI line color too
end

xticks(x);
xticklabels(string(statsTable.name));
xtickangle(45);
ax = gca;
ax.TickLabelInterpreter = 'none';



ylabel('\zeta (AVG of methods)');
title('All materials (sorted): AVG mean \pm 95% CI');

legend(h, string(statsTable.name), 'Location','southwest', 'Interpreter','none');

hold off;



function [mu, lo, hi, n] = mean_ci95(x)
    x = x(:);
    x = x(~isnan(x));   % ignore NaNs
    n = numel(x);

    if n == 0
        mu = NaN; lo = NaN; hi = NaN;
        return
    elseif n == 1
        mu = x;
        lo = NaN; hi = NaN;   % can't form CI with 1 sample
        return
    end

    mu = mean(x);
    s  = std(x, 0);           % sample std (N-1)
    se = s / sqrt(n);
    tcrit = tinv(0.975, n-1); % 95% two-sided
    lo = mu - tcrit*se;
    hi = mu + tcrit*se;
end


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
