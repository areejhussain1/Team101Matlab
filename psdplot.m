function psdplot(az_g, name)
% Fast PSD plot in G^2/Hz and dB/Hz using dynamic Welch parameters
% Optimized for repeated calls

    persistent Fs xlims
    if isempty(Fs)
        Fs    = 6400;       % Hz
        xlims = [0 500];
    end

    % Ensure column vector
    az_g = az_g(:);
    L = numel(az_g);

    % Guard against very short inputs
    if L < 16
        error('Input vector az_g is too short for PSD estimation.');
    end

    % -----------------------------
    % Dynamic Welch parameter setup
    % -----------------------------
    % Use about 8 segments when possible, but clamp to practical limits
    nwin = floor(L / 8);

    % Clamp window length for stability/speed
    nwin = max(256, nwin);      % minimum useful window
    nwin = min(4096, nwin);     % cap for speed on long signals
    nwin = min(nwin, L);        % cannot exceed signal length

    % Make window length even for neat 50% overlap
    nwin = 2 * floor(nwin / 2);

    % Fallback if signal is shorter than 256 samples
    if nwin < 32
        nwin = max(16, 2 * floor(L / 2));
    end

    % Dynamic Welch parameters
    window   = hamming(nwin);
    noverlap = floor(0.5 * nwin);
    nfft     = 2^nextpow2(nwin);

    % PSD with 95% confidence bounds
    [pxx, f, pxxc] = pwelch(az_g, window, noverlap, nfft, Fs, ...
                            'ConfidenceLevel', 0.95);

    % Convert once for dB plot
    pxx_dB  = 10*log10(pxx);
    pxxc_dB = 10*log10(pxxc);

    % Plot
    figure;
    t = tiledlayout(2,1, 'TileSpacing','compact', 'Padding','compact');

    % Linear PSD
    ax1 = nexttile;
    plot(f, pxx, 'LineWidth', 1);
    hold(ax1, 'on');
    plot(f, pxxc(:,1), '-.');
    plot(f, pxxc(:,2), '-.');
    grid(ax1, 'on');
    xlim(ax1, xlims);
    ylabel(ax1, 'PSD (G^2/Hz)');
    title(ax1, "PSD of " + name + " with ±95% confidence bounds",'Interpreter','none');
    ax1.XAxis.Exponent = 0;

    % dB PSD
    ax2 = nexttile;
    plot(f, pxx_dB, 'LineWidth', 1);
    hold(ax2, 'on');
    plot(f, pxxc_dB(:,1), '-.');
    plot(f, pxxc_dB(:,2), '-.');
    grid(ax2, 'on');
    xlim(ax2, xlims);
    xlabel(ax2, 'Frequency (Hz)');
    ylabel(ax2, 'PSD (dB/Hz)');
    ax2.XAxis.Exponent = 0;

    % Keep same Hz scale
    linkaxes([ax1, ax2], 'x');
end

% function psdplot(az_g,name)
% %close all
% 
% % Acceleration data vector
% % Replace this with your actual data
% %accel = your_accel_data;   % e.g. accel = data(:,1);
% 
% if isempty(Fs)
% 
% 
% % Sampling frequency
% Fs = 6400;  % Hz
% 
% % Welch parameters
% window = hamming(1024);    % window length
% noverlap = 512;            % 50% overlap
% nfft = 1024;               % FFT length
% L=numel(az_g);
% maxNperseg = 2^14;                           % 16384
% nperseg = min(maxNperseg, max(256, floor(L/8)));
% nperseg = min(nperseg, L);
% 
% 
% % Plot PSD using pwelch
% % figure;
% [pxx,f,pxxc] = pwelch(az_g, window, noverlap, nfft, Fs,'ConfidenceLevel',.95);
% %[pxx,f,pxxc] = pwelch(az_g, nperseg, noverlap, nfft, Fs);
% % grid on;
% % title('Power Spectral Density of Acceleration Signal');
% % xlabel('Frequency (Hz)');
% % ylabel('Power/Frequency (dB/Hz)');
% 
% figure;
% plot(f,pxx, 'LineWidth', 1);
% grid on;
% hold on;
% plot(f,pxxc,'-.')
% xlim([0 500]);
% 
% title("PSD of " + name + " with ±95% confidence Bounds");
% xlabel('Frequency (Hz)');
% ylabel('PSD (G^2/Hz)');
% 
% % Force MATLAB not to use ×10^n axis notation
% ax = gca;
% ax.XAxis.Exponent = 0;
% 
% % PLOT IN DB
% % figure;
% % plot(f,10*log10(pxx), 'LineWidth', 1);
% % grid on;
% % hold on;
% % plot(f,10*log10(pxxc),'-.')
% % xlim([0 500]);
% % 
% % title('Power Spectral Density of Acceleration Signal with ±95% confidence Bounds');
% % xlabel('Frequency (Hz)');
% % ylabel('PSD (dB/Hz)');
% % 
% % % Force MATLAB not to use ×10^n axis notation
% % ax = gca;
% % ax.XAxis.Exponent = 0;
% % end