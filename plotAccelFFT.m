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

figure('Color','w');
plot(f, P1 , 'LineWidth', 1);
grid on;
hold on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');

title('FFT of Az');
xline(f1,"o--")
xline(f2,"o--")
xline(peak_f,"r--")

if ~isempty(maxFreq)
    xlim([0 maxFreq]);
end

% Plot magnitude spectrum
figure('Color','w');
plot(f, db+100, 'LineWidth', 1);
grid on;
hold on;
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
title(sprintf('FFT of %s', axisLabel));

xline(f1,"o--")
xline(f2,"o--")
xline(peak_f,"r--")

if ~isempty(maxFreq)
    xlim([0 maxFreq]);
end


% Half-power bandwidth
[max_mag, i_peak] = max(P1);
peak_f = f(i_peak);

hp_mag = max_mag / sqrt(2);

[~, i_left] = min(abs(P1(1:i_peak) - hp_mag));
f1 = f(i_left);

[~, i_right_rel] = min(abs(P1(i_peak:end) - hp_mag));
i_right = i_peak + i_right_rel - 1;
f2 = f(i_right);

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
    A_mag = abs(x_peaks_u);                  % magnitude in g
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
            fprintf('Using %d peaks >= 10 g after neighbor-outlier filter\n', numel(A));
            fprintf('Mean delta = %.4f\n', delta_bar);
            fprintf('Loss Factor (eta_log)    = %.4f\n', eta_log);
            fprintf('Damping Ratio (zeta_log) = %.4f\n', zeta_log);

            % Optional: plot time signal with peaks used for log dec
 %           figure('Color','w');
 %           plot(t_sec, x_detrend, 'b-'); hold on;
            % Restore sign just for plotting markers in right direction
            signs_used = sign(interp1(locs_u, x_peaks_u, locs_big, 'nearest', 'extrap'));
 %           plot(locs_big, signs_used .* A, 'ro', 'MarkerFaceColor','r');
            grid on;
            xlabel('Time (s)');
            ylabel(axisLabel);
            title (sprintf('Time response and peaks used for log decrement (%s)', axisToUse));
            legend('x(t)', 'Peaks used');
        end
    end
end
