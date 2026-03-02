    clc; close all; clear

%function [t_sec, ax_g, ay_g, az_g] = captureAccelChunk()
    % === USER SETTINGS ===
    port      = "COM5";   % <-- your Pico's COM port
    baudRate  = 115200;
    SENSOR_ID = 0;        % which sensor id to use
    LSB_TO_G  = 0.1;      % ADXL372: ~0.1 g per code (100 mg/LSB)
    N_SAMPLES = 6400*3;     % how many samples to capture (max)

    % Close old serial objects on this port (for very old MATLABs)
    old = instrfind("Port", port); %#ok<INSTRFND>
    if ~isempty(old)
        try fclose(old); end %#ok<TRYNC>
        delete(old);
    end

    % Open serial port
    fprintf("Opening %s at %d baud...\n", port, baudRate);
    s = serialport(port, baudRate, "Timeout", 1);
    configureTerminator(s, "LF");
    flush(s);

    t_us   = zeros(N_SAMPLES, 1);
    ax_raw = zeros(N_SAMPLES, 1);
    ay_raw = zeros(N_SAMPLES, 1);
    az_raw = zeros(N_SAMPLES, 1);

    n  = 0;
    t0 = [];

    fprintf("Collecting up to %d samples for sensor %d...\n", N_SAMPLES, SENSOR_ID);

    try
        while n < N_SAMPLES
            line = readline(s);   % blocks up to Timeout seconds
            line = strtrim(line);
            if isempty(line)
                continue;
            end

            parts = split(line, ',');
            if numel(parts) ~= 5
                continue;   % skip non-data lines
            end

            vals = str2double(parts);
            if any(isnan(vals))
                continue;
            end

            ts_us  = vals(1);
            sid    = vals(2);
            x_raw  = vals(3);
            y_raw  = vals(4);
            z_raw  = vals(5);

            if sid ~= SENSOR_ID
                continue;
            end

            if isempty(t0)
                t0 = ts_us;
            end

            n = n + 1;
            t_us(n)   = ts_us - t0;
            ax_raw(n) = x_raw;
            ay_raw(n) = y_raw;
            az_raw(n) = z_raw;
        end
    catch ME
        fprintf("Capture interrupted: %s\n", ME.message);
    end

    % Close serial port
    clear s;

    if n == 0
        warning("No samples captured – nothing to analyze.");
        t_sec = [];
        ax_g  = [];
        ay_g  = [];
        az_g  = [];
        return;
    end

    % Trim arrays to actual length
    t_us   = t_us(1:n);
    ax_raw = ax_raw(1:n);
    ay_raw = ay_raw(1:n);
    az_raw = az_raw(1:n);

    fprintf("Captured %d samples.\n", n);

    % Convert to time in seconds and g
    Fs   = 6400;                 % ADXL372 ODR in Hz
    t_sec = (0:n-1).' / Fs;      % 0, 1/Fs, 2/Fs, ..., (n-1)/Fs
    ax_g  = ax_raw * LSB_TO_G;
    ay_g  = ay_raw * LSB_TO_G;
    az_g  = az_raw * LSB_TO_G;

    % --- Print mean and std (quick sanity check) ---
    fprintf("Ax: mean = %.2f g, std = %.2f g\n", mean(ax_g), std(ax_g));
    fprintf("Ay: mean = %.2f g, std = %.2f g\n", mean(ay_g), std(ay_g));
    fprintf("Az: mean = %.2f g, std = %.2f g\n", mean(az_g), std(az_g));

    % --- Save to base workspace for convenience ---
    assignin('base', 't_sec', t_sec);
    assignin('base', 'ax_g',  ax_g);
    assignin('base', 'ay_g',  ay_g);
    assignin('base', 'az_g',  az_g);


    % --- Plot the chunk ---
    figure('Color','w');
    plot(t_sec, ax_g, '-', t_sec, ay_g, '-', t_sec, az_g, '-');
    xlabel('Time (s)');
    ylabel('Acceleration (g)');
    title(sprintf('Captured chunk (sensor %d)', SENSOR_ID));
    legend({'Ax','Ay','Az'}, 'Location', 'best');
    grid on;

    fprintf("Saved t_sec, ax_g, ay_g, az_g to workspace.\n");
    %% 

% plotAccelFFT.m
% Uses ax_g / ay_g / az_g from workspace and a known sample rate Fs.

% === USER SETTINGS ===
axisToUse = 'Az';     % 'Ax', 'Ay', or 'Az'
Fs        = 6400;     % <-- your ODR in Hz (very important!)
maxFreq   = [500];       % e.g. 3000 to limit x-axis, [] = full Nyquist

% --- Pick the axis data from workspace ---
switch upper(axisToUse)
    case 'AX'
        if ~exist('ax_g','var'), error('ax_g not found in workspace'); end
        x = ax_g(:);
        axisLabel = 'Ax (g)';
    case 'AY'
        if ~exist('ay_g','var'), error('ay_g not found in workspace'); end
        x = ay_g(:);
        axisLabel = 'Ay (g)';
    case 'AZ'
        if ~exist('az_g','var'), error('az_g not found in workspace'); end
        x = az_g(:);
        axisLabel = 'Az (g)';
    otherwise
        error('axisToUse must be ''Ax'', ''Ay'', or ''Az''.');
end

N = numel(x);
if N < 2
    error('Not enough samples for FFT.');
end

fprintf('Using Fs = %.1f Hz, N = %d samples\n', Fs, N);

% --- Reconstruct time vector (uniform sampling) ---
t_sec = (0:N-1).' / Fs;

% --- Remove DC offset for both FFT and time-domain work ---
x_detrend = x - mean(x);

%% ==========================
%  HALF-POWER METHOD (FFT)
%  ==========================
w  = hann(N);
xw = x_detrend .* w;

% Compute FFT
X  = fft(xw);
P2 = abs(X) / N;                 % two-sided
P1 = P2(1:floor(N/2)+1);         % single-sided
P1(2:end-1) = 2*P1(2:end-1);

db=20*log10(abs(P1));

% Frequency axis
f = Fs*(0:floor(N/2))/N;

% Half-power bandwidth
[max_mag, i_peak] = max(P1);
peak_f = f(i_peak);

hp_mag = max_mag / sqrt(2);

[~, i_left] = min(abs(P1(1:i_peak) - hp_mag*.95));
f1 = f(i_left);

[~, i_right_rel] = min(abs(P1(i_peak:end) - hp_mag));
i_right = i_peak + i_right_rel - 1;
f2 = f(i_right);

% Plot magnitude spectrum
figure('Color','w');
plot(f, P1, 'LineWidth', 1);
grid on;
hold on;
xlabel('Frequency (Hz)');
ylabel('|X(f)| (g \cdot windowed units)');
title(sprintf('FFT of %s', axisLabel));

if ~isempty(maxFreq)
    xlim([0 maxFreq]);
end

xline(f1,"o--")
xline(f2,"o--")
xline(peak_f,"r--")

% Plot magnitude spectrum
figure('Color','w');
plot(f, db, 'LineWidth', 1);
grid on;
hold on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
title(sprintf('FFT of %s', axisLabel));

if ~isempty(maxFreq)
    xlim([0 maxFreq]);
end

xline(peak_f,"r--")



df   = f2 - f1;
eta_hp  = df / peak_f;         % loss factor (half-power)
zeta_hp = df / (2*peak_f);     % damping ratio (half-power)

fprintf('--- Half-power method ---\n');
fprintf('Peak frequency = %.3f Hz\n', peak_f);
fprintf('f1 = %.3f Hz, f2 = %.3f Hz\n', f1, f2);
fprintf('Loss Factor (eta_HP)   = %.4f\n', eta_hp);
fprintf('Damping Ratio (zeta_HP) = %.4f\n', zeta_hp);

%% ==========================
%  LOGARITHMIC DECREMENT (time domain)
%  ==========================
% We use x_detrend (unwindowed), detect peaks, skip clipped region,
% then compute log decrement only from peaks >= 10 g and not obvious outliers.

% Estimate period from peak frequency (from half-power method)
Tn = 1 / peak_f;

% Peak detection: enforce a minimum spacing so we pick ~1 peak per cycle
minPeakDist_sec = 0.5 * Tn;    % you can tune between 0.5–1.0
[x_peaks, locs] = findpeaks(x_detrend, t_sec, ...
    'MinPeakDistance', minPeakDist_sec);

if numel(x_peaks) < 3
    warning('Not enough peaks found for log decrement method.');
else
    % --- Handle clipping at the start ---
    clip_level = max(abs(x_detrend));
    tol = 1e-3 * clip_level;   % tolerance for "near clipped"

    clip_idx = find(abs(x_detrend) >= clip_level - tol);
    if ~isempty(clip_idx)
        t_clip_end = t_sec(clip_idx(end));    % end of clipped region
        keep_clip  = locs > t_clip_end;      % peaks after clipping
        x_peaks_u  = x_peaks(keep_clip);
        locs_u     = locs(keep_clip);
    else
        % No obvious clipping: use all peaks
        x_peaks_u = x_peaks;
        locs_u    = locs;
    end

    % --- 1) Apply 10 g magnitude threshold ---
    A_mag = x_peaks_u;                  % magnitude in g, was abs(x_peaks_u)
    keep_big = A_mag >= 5;                  % only peaks >= 10 g
    A1       = A_mag(keep_big);
    locs1    = locs_u(keep_big);

    if numel(A1) < 2
        warning('Not enough peaks >= 10 g for log decrement calculation.');
    else
        % --- 2) Remove local "outlier" peaks that are much smaller than neighbors ---
        % Criterion: for interior peaks i, if A1(i) < alpha * min(A1(i-1), A1(i+1)),
        % mark it as outlier. alpha can be tuned; here ~60% of neighbor min.
        alpha = 0.8;  % tighten/loosen this as needed

        keep_neighbor = true(size(A1));

        if numel(A1) >= 3
            for k = 2:numel(A1)-1
                neighbor_min = min(A1(k-1), A1(k+1));
                if A1(k) < alpha * neighbor_min
                    keep_neighbor(k) = false;
                end
            end
        end
        % You can also choose to apply a similar check to endpoints if you want.
        % For now, first and last peak are always kept.

        A  = A1(keep_neighbor);
        locs_big = locs1(keep_neighbor);

        if numel(A) < 2
            warning('Not enough non-outlier peaks for log decrement calculation.');
        else
            % Compute log decrements between successive "good" peaks
            deltas = log(A(1:end-1) ./ A(2:end));  % δ_i = ln(A_i / A_{i+1})
            delta_bar = mean(deltas);

            % Damping ratio from log decrement:
            % zeta = δ / sqrt(4π² + δ²)
            zeta_log = delta_bar / sqrt(4*pi^2 + delta_bar^2);
            eta_log  = 2 * zeta_log;   % loss factor

            fprintf('\n--- Logarithmic decrement method ---\n');
            fprintf('Using %d peaks >= 5 g after neighbor-outlier filter\n', numel(A));
            fprintf('Mean delta = %.4f\n', delta_bar);
            fprintf('Loss Factor (eta_log)    = %.4f\n', eta_log);
            fprintf('Damping Ratio (zeta_log) = %.4f\n', zeta_log);

            % Optional: plot time signal with peaks used for log dec
            figure('Color','w');
            plot(t_sec, x_detrend, 'b-'); hold on;
            % Restore sign just for plotting markers in right direction
            signs_used = sign(interp1(locs_u, x_peaks_u, locs_big, 'nearest', 'extrap'));
            plot(locs_big, signs_used .* A, 'ro', 'MarkerFaceColor','r');
            grid on;
            xlabel('Time (s)');
            ylabel(axisLabel);
            title('Time response and peaks used for log decrement');
            legend('x(t)', 'Peaks used');
        end
    end
end

delta_eta = abs(eta_hp-eta_log)/eta_log * 100;
tol_eta = 20;
fprintf('Delta Loss Percent       = %.4f\n', delta_eta)
if delta_eta < tol_eta
    fprintf('Likely good data');
    savedata
end
