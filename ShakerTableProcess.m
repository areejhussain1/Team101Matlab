%% ShakerTableProcess.m
% =====================================================================
% Master processing script for broadband random vibration shaker table test.
%
% INPUTS:
%   - CSV file from ShakerTableMonitor.c on the SD card
%     Format: timestamp_us, sensor_id, x_raw, y_raw, z_raw
%
% OUTPUTS (per sensor, per axis):
%   - Response PSD in g^2/Hz (Welch's method, 95% confidence bounds)
%   - RMS acceleration in g
%   - Summary table printed to command window
%   - All results saved to a .mat file for later ANSYS comparison
%
% USAGE:
%   1. Copy run_XXX.csv from SD card to your working directory
%   2. Set USER SETTINGS below
%   3. Run this script
% =====================================================================

clc; close all; clear;

%% ======================== USER SETTINGS =============================

% --- File to process ---
csv_file = 'run_001.csv';      % Path to the CSV from the SD card

% --- Sensor / sampling config ---
Fs          = 6400;             % ADXL372 ODR in Hz (must match C code)
LSB_TO_G    = 0.1;             % ADXL372 sensitivity: 100 mg/LSB
NUM_SENSORS = 5;                % Number of accelerometers (0..4)

% --- Which axes to process ---
% Set to true/false depending on which axes matter for your fixture.
% For a vertical shaker the primary response is usually Z, but all
% three are computed so you can check cross-axis coupling.
process_ax = true;
process_ay = true;
process_az = true;

% --- PSD estimation parameters ---
% These control the Welch PSD calculation.  Defaults are good for
% broadband random vibration; adjust if you need finer frequency
% resolution (increase nfft) or smoother curves (decrease nfft).
psd_nfft       = 4096;         % FFT length (frequency resolution = Fs/nfft)
psd_overlap    = 0.5;          % Fractional overlap (0.5 = 50%)
psd_window_fn  = @hamming;     % Window function handle

% --- Plot frequency range ---
freq_range = [0 3200];         % [min max] Hz for PSD plots
                                % Nyquist is Fs/2 = 3200 Hz

% --- Output ---
save_results = true;           % Save results struct to .mat file
output_mat   = '';             % Leave empty to auto-name from csv_file


%% ======================== LOAD CSV ==================================

fprintf('Loading %s ...\n', csv_file);
raw = readmatrix(csv_file);

% The CSV has a text header row; readmatrix may produce a NaN first row.
% Remove any rows with NaN (header or corrupt lines).
raw(any(isnan(raw), 2), :) = [];

timestamp_us = raw(:, 1);
sensor_id    = raw(:, 2);
x_raw        = raw(:, 3);
y_raw        = raw(:, 4);
z_raw        = raw(:, 5);

fprintf('Loaded %d total samples across %d sensors.\n', ...
    size(raw, 1), numel(unique(sensor_id)));


%% ======================== SPLIT BY SENSOR ===========================

% Pre-allocate cell arrays: one entry per sensor
ax_g = cell(NUM_SENSORS, 1);
ay_g = cell(NUM_SENSORS, 1);
az_g = cell(NUM_SENSORS, 1);
t_sec = cell(NUM_SENSORS, 1);

for s = 0 : NUM_SENSORS - 1
    mask = (sensor_id == s);
    n = sum(mask);

    if n == 0
        fprintf('[WARN] Sensor %d: no samples found.\n', s);
        continue;
    end

    % Convert raw codes to g
    ax_g{s+1} = x_raw(mask) * LSB_TO_G;
    ay_g{s+1} = y_raw(mask) * LSB_TO_G;
    az_g{s+1} = z_raw(mask) * LSB_TO_G;

    % Reconstruct uniform time vector from known sample rate.
    % The C-side timestamps are coarse (one per FIFO drain), so for
    % spectral analysis we use the deterministic sample index instead.
    t_sec{s+1} = (0 : n-1).' / Fs;

    fprintf('Sensor %d: %d samples (%.2f s)\n', s, n, n / Fs);
end


%% ======================== PSD + RMS PER SENSOR ======================

% Welch parameters derived from user settings
win_len  = min(psd_nfft, Fs);       % Cap window to 1 second of data
win_len  = min(win_len, psd_nfft);
noverlap = floor(psd_overlap * win_len);
window   = psd_window_fn(win_len);

% Storage for summary table
summary = struct();

% Axes to loop over
axis_labels = {};
axis_data   = {};
if process_ax, axis_labels{end+1} = 'Ax'; axis_data{end+1} = ax_g; end
if process_ay, axis_labels{end+1} = 'Ay'; axis_data{end+1} = ay_g; end
if process_az, axis_labels{end+1} = 'Az'; axis_data{end+1} = az_g; end

% Results struct for saving
results = struct();
results.csv_file   = csv_file;
results.Fs         = Fs;
results.LSB_TO_G   = LSB_TO_G;
results.freq_range = freq_range;
results.psd_nfft   = psd_nfft;
results.sensors    = struct();

for s = 0 : NUM_SENSORS - 1
    si = s + 1;     % MATLAB 1-index

    if isempty(t_sec{si})
        continue;
    end

    n_samples = numel(t_sec{si});

    % Skip sensors with too few samples for the chosen FFT length
    if n_samples < win_len
        fprintf('[WARN] Sensor %d: only %d samples, need >= %d. Skipping PSD.\n', ...
            s, n_samples, win_len);
        continue;
    end

    % Create a figure for this sensor: one subplot row per axis
    n_axes = numel(axis_labels);
    fig = figure('Name', sprintf('Sensor %d PSD', s), ...
                 'Color', 'w', 'Position', [100 100 900 300*n_axes]);
    tl = tiledlayout(n_axes, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, sprintf('Sensor %d – Response PSD', s), 'FontSize', 14);

    sensor_results = struct();

    for a = 1 : n_axes
        data_all = axis_data{a};
        data     = data_all{si};
        label    = axis_labels{a};

        % Remove DC offset before PSD estimation
        data = data - mean(data);

        % --- Welch PSD with 95% confidence interval ---
        [pxx, f, pxxc] = pwelch(data, window, noverlap, psd_nfft, Fs, ...
                                'ConfidenceLevel', 0.95);

        % --- RMS from time domain (equivalent to sqrt of integrated PSD) ---
        rms_g = rms(data);

        % --- Also compute RMS from PSD for cross-check ---
        df = f(2) - f(1);
        rms_from_psd = sqrt(sum(pxx) * df);

        % --- Store results ---
        field = lower(label);   % 'ax', 'ay', 'az'
        sensor_results.(field).f       = f;
        sensor_results.(field).psd     = pxx;
        sensor_results.(field).psd_lo  = pxxc(:, 1);
        sensor_results.(field).psd_hi  = pxxc(:, 2);
        sensor_results.(field).rms_g   = rms_g;
        sensor_results.(field).rms_psd = rms_from_psd;
        sensor_results.(field).n       = n_samples;

        % --- Plot ---
        ax_h = nexttile;
        semilogy(f, pxx, 'LineWidth', 1.2); hold on;
        semilogy(f, pxxc(:,1), '-.', 'Color', [0.6 0.6 0.6]);
        semilogy(f, pxxc(:,2), '-.', 'Color', [0.6 0.6 0.6]);
        grid on;
        xlim(freq_range);
        ylabel(sprintf('%s  PSD (g^2/Hz)', label));
        legend('PSD', '95% CI lower', '95% CI upper', 'Location', 'best');
        ax_h.XAxis.Exponent = 0;

        if a == n_axes
            xlabel('Frequency (Hz)');
        end

        % Print to command window
        fprintf('  Sensor %d %s:  RMS = %.4f g  |  RMS(PSD) = %.4f g\n', ...
            s, label, rms_g, rms_from_psd);
    end

    results.sensors(si) = sensor_results;
end


%% ======================== SUMMARY TABLE =============================

fprintf('\n======================================================\n');
fprintf('  SENSOR SUMMARY  –  %s\n', csv_file);
fprintf('======================================================\n');
fprintf('%-8s', 'Sensor');
for a = 1 : numel(axis_labels)
    fprintf('  %s RMS (g)  ', axis_labels{a});
end
fprintf('\n');
fprintf(repmat('-', 1, 8 + numel(axis_labels) * 14)); fprintf('\n');

for s = 0 : NUM_SENSORS - 1
    si = s + 1;
    if isempty(t_sec{si}), continue; end

    fprintf('%-8d', s);
    for a = 1 : numel(axis_labels)
        field = lower(axis_labels{a});
        if isfield(results.sensors(si), field)
            fprintf('  %10.4f  ', results.sensors(si).(field).rms_g);
        else
            fprintf('  %10s  ', 'N/A');
        end
    end
    fprintf('\n');
end
fprintf('======================================================\n');


%% ======================== OVERLAY PLOT (ALL SENSORS) ================

% One overlay figure per axis so you can see how response varies
% across the fixture — useful for spotting modes and comparing with
% ANSYS node locations.

colors = lines(NUM_SENSORS);

for a = 1 : numel(axis_labels)
    label = axis_labels{a};
    field = lower(label);

    figure('Name', sprintf('All Sensors – %s PSD', label), ...
           'Color', 'w', 'Position', [100 100 1000 500]);

    hold on; grid on;
    legend_entries = {};

    for s = 0 : NUM_SENSORS - 1
        si = s + 1;
        if isempty(t_sec{si}), continue; end
        if ~isfield(results.sensors(si), field), continue; end

        semilogy(results.sensors(si).(field).f, ...
                 results.sensors(si).(field).psd, ...
                 'LineWidth', 1.2, 'Color', colors(si, :));

        legend_entries{end+1} = sprintf('Sensor %d (%.3f g_{rms})', ...
            s, results.sensors(si).(field).rms_g); %#ok<SAGROW>
    end

    xlim(freq_range);
    xlabel('Frequency (Hz)');
    ylabel(sprintf('%s  PSD (g^2/Hz)', label));
    title(sprintf('Response PSD – %s – All Sensors', label));
    legend(legend_entries, 'Location', 'best');
    ax_h = gca; ax_h.XAxis.Exponent = 0;
end


%% ======================== SAVE ======================================

if save_results
    if isempty(output_mat)
        [~, base, ~] = fileparts(csv_file);
        output_mat = [base '_results.mat'];
    end

    save(output_mat, 'results', 'ax_g', 'ay_g', 'az_g', 't_sec');
    fprintf('\nResults saved to %s\n', output_mat);
    fprintf('Fields in results.sensors(i).az:\n');
    fprintf('  .f        – frequency vector (Hz)\n');
    fprintf('  .psd      – PSD (g^2/Hz)\n');
    fprintf('  .psd_lo/hi – 95%% confidence bounds\n');
    fprintf('  .rms_g    – RMS acceleration (g)\n');
end

fprintf('\nDone. Compare these PSD curves and RMS values against your ANSYS output.\n');
