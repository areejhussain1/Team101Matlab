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
        fileName, fn, zeta_HP, zeta_log, eta_HP, eta_log, delta_eta);

    if currentName == ""
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

    vals = [zhp; zlog; zavg];
    g    = [ones(numel(zhp),1); 2*ones(numel(zlog),1); 3*ones(numel(zavg),1)];

    boxchart(g, vals);
    set(gca, 'XTick', 1:3, 'XTickLabel', {'HP','LOG','AVG'});

    x = 1:3;
    errorbar(x, mus, mus-los, his-mus, 'r', ...
        'LineStyle','none', 'LineWidth',1.3, 'CapSize',10);
    plot(x, mus, 'kd', 'MarkerFaceColor','r', 'MarkerSize',6);

    ylabel('\zeta');
    title(sprintf('%s | AVG=%.4f', key, row.zeta_avg_mean), 'Interpreter','none');

    hold off;
end

title(t, 'Per material: distribution (box plot) + mean \pm 95% CI');

%
% PLOTTING ALL THE MATERIALS AVG ON ONE (FILTERABLE VIA INDEX INPUT)
%

% Example filter usage:
%   idxKeep = 1:5;                          % first 5 materials in statsTable
%   idxKeep = statsTable.avg_n >= 5;        % logical mask example
%   idxKeep = ~ismember(string(statsTable.name), ["rub","SCPOLY"]); % by name
idxKeep = 1:height(statsTable);  % <-- change this to filter

plot_material_ci_filtered(statsTable, idxKeep, ...
    'FigureName', 'All materials (filtered): AVG mean \pm 95% CI (sorted)', ...
    'BlockSize', 7, ...
    'ShowXTicks', false, ...
    'FontSizeName', 12, ...
    'FontSizeMu', 8);
%%



idxKeep = ismember(string(statsTable.name), ["AEAR_R012","AEAR_SD125","AEAR_SD40AL","AEAR_blue_cured","AEAR_blue","bare"]);  

plot_material_ci_filtered(statsTable, idxKeep, ...
    'FigureName', 'All AEARO Materials: AVG mean \pm 95% CI (sorted)', ...
    'BlockSize', 7, ...
    'ShowXTicks', false, ...
    'FontSizeName', 12, ...
    'FontSizeMu', 8);


%% =========================
% FUNCTIONS
%% =========================

% PLOTS A FILTERED SET OF MATERIALS ON CANDLESTICK WITH MEAN LABELED AND
% CONFIDENCE INTERVAL AS ERROR BARS
function plot_material_ci_filtered(statsTable, idxKeep, varargin)
% Inputs
%   statsTable : table with variables: name, zeta_avg_mean, zeta_avg_ci_lo, zeta_avg_ci_hi
%   idxKeep    : indices (e.g. [1 3 7]) OR logical mask (height(statsTable)x1)
%
% Name-Value options (optional)
%   'FigureName'  : figure name (default: 'Filtered materials: AVG mean ± 95% CI')
%   'BlockSize'   : palette block size (default: 7)
%   'ShowXTicks'  : true/false (default: false; names are annotated near points)
%   'FontSizeName': font size for name labels (default: 10)
%   'FontSizeMu'  : font size for mean callouts (default: 8)

    % ---- Parse options ----
    p = inputParser;
    p.addParameter('FigureName', 'Filtered materials: AVG mean \pm 95% CI', @(s)isstring(s)||ischar(s));
    p.addParameter('BlockSize', 7, @(x)isnumeric(x)&&isscalar(x)&&x>=1);
    p.addParameter('ShowXTicks', false, @(x)islogical(x)&&isscalar(x));
    p.addParameter('FontSizeName', 10, @(x)isnumeric(x)&&isscalar(x));
    p.addParameter('FontSizeMu', 8, @(x)isnumeric(x)&&isscalar(x));
    p.parse(varargin{:});
    opt = p.Results;

    % ---- Normalize idxKeep to numeric indices ----
    if islogical(idxKeep)
        idxKeep = find(idxKeep);
    end
    idxKeep = idxKeep(:);

    if isempty(idxKeep)
        warning('plot_material_ci_filtered:EmptySelection', 'idxKeep is empty. Nothing to plot.');
        return
    end

    % ---- Filter and sort within the selection ----
    T = statsTable(idxKeep, :);
    T = sortrows(T, 'zeta_avg_mean', 'descend');

    % ---- Extract ----
    names = string(T.name);
    mu = T.zeta_avg_mean;
    lo = T.zeta_avg_ci_lo;
    hi = T.zeta_avg_ci_hi;

    N = height(T);
    x = (1:N)';

    % ---- Colors: switch palette every BlockSize ----
    block = opt.BlockSize;
    palettes = {@lines, @parula, @turbo, @hsv, @spring, @summer, @autumn, @winter, @cool, @hot, @copper};

    cols = zeros(N,3);
    idx = 1;
    pal_i = 1;

    while idx <= N
        m = min(block, N - idx + 1);
        cmap = palettes{pal_i}(max(block, m));
        cols(idx:idx+m-1, :) = cmap(1:m, :);

        idx = idx + m;
        pal_i = pal_i + 1;
        if pal_i > numel(palettes)
            pal_i = 1;
        end
    end

    % ---- Plot ----
    figure('Name', opt.FigureName);
    hold on; grid on;

    h = gobjects(N,1);

    yRange = max(hi) - min(lo);
    if ~isfinite(yRange) || yRange == 0
        yRange = 1;
    end
    dy_name = 0.02 * yRange;   % offset for bottom name label
    dx_mu   = 0.08;            % x offset for mean callout
    dy_mu   = 0.00 * yRange;   % y offset for mean callout

    for k = 1:N
        h(k) = errorbar(x(k), mu(k), mu(k)-lo(k), hi(k)-mu(k), 'o', ...
            'LineStyle','none', 'LineWidth',1.5, 'CapSize',10, ...
            'MarkerFaceColor', cols(k,:), 'MarkerEdgeColor', cols(k,:), ...
            'Color', cols(k,:));

        % Name label at bottom of CI
        text(x(k), lo(k) - dy_name, names(k), ...
            'Rotation', 90, ...
            'HorizontalAlignment', 'right', ...
            'VerticalAlignment', 'middle', ...
            'Interpreter', 'none', ...
            'FontSize', opt.FontSizeName);

        % Mean callout near marker
        text(x(k) + dx_mu, mu(k) + dy_mu, sprintf('%.4f', mu(k)), ...
            'Interpreter','none', ...
            'FontSize', opt.FontSizeMu, ...
            'Color', cols(k,:), ...
            'BackgroundColor', 'w', ...
            'EdgeColor', cols(k,:), ...
            'Margin', 2, ...
            'HorizontalAlignment', 'left', ...
            'VerticalAlignment', 'middle');
    end

    ylim([min(lo) - 0.15*yRange, max(hi) + 0.15*yRange]);

    if opt.ShowXTicks
        xticks(x);
        xticklabels(names);
        xtickangle(45);
        ax = gca;
        ax.TickLabelInterpreter = 'none';
    else
        xticks(x);
        xticklabels([]);
    end

    ylabel('\zeta % (AVG of methods)');
    title(opt.FigureName, 'Interpreter','none');
    legend(h, names, 'Location','southwest', 'Interpreter','none');
    xlim([0,numel(idxKeep)+1])
    ylim([0 ,2.5])

    hold off;
end

% USES CALCULATED ZETA OR ETA VALUES FOR EACH TRIAL TO FIND CONFIDENCE
% INTERVALS DYNAMICALLY ADJUSTING FOR NUMBER OF TRIALS
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

% USES AXIS ACCEL AND SAMPLE FREQ TO CALCULATE ZETA VIA BOTH METHODS.
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
[~, i_left] = min(abs(P1(1:i_peak) - hp_mag*0.95));
f1 = f(i_left);

[~, i_right_rel] = min(abs(P1(i_peak:end) - hp_mag));
i_right = i_peak + i_right_rel - 1;
f2 = f(i_right);

df = f2 - f1;
eta_hp  = df / peak_f * 100;
zeta_hp = df / (2*peak_f) * 100;

%% ==========================
%  LOGARITHMIC DECREMENT (time domain)
%  ==========================
if peak_f <= 0 || isnan(peak_f)
    zeta_log = NaN; eta_log = NaN;
else
    Tn = 1 / peak_f;

    minPeakDist_sec = 0.5 * Tn;
    [x_peaks, locs] = findpeaks(x_detrend, t_sec, 'MinPeakDistance', minPeakDist_sec);

    if numel(x_peaks) < 3
        zeta_log = NaN; eta_log = NaN;
    else
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

        A_mag = abs(x_peaks_u);
        keep_big = A_mag >= 5;
        A1 = A_mag(keep_big);

        if numel(A1) < 2
            zeta_log = NaN; eta_log = NaN;
        else
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

                zeta_log = delta_bar / sqrt(4*pi^2 + delta_bar^2) * 100;
                eta_log  = 2 * zeta_log;
            end
        end
    end
end

%% ==========================
%  ERROR CALC (reference)
%  ==========================
if isnan(eta_log) || eta_log == 0
    delta_eta = NaN;
else
    delta_eta = abs(eta_hp - eta_log) / eta_log * 100;
end
end
