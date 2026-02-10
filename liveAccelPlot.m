function liveAccelPlot()
    % === USER SETTINGS ===
    port     = "COM3";    % <-- your Pico's COM port
    baudRate = 115200;    % must match firmware
    SENSOR_ID = 0;        % which sensor_id to show
    LSB_TO_G  = 0.1;      % ADXL372 ~0.1 g per code (100 mg/LSB)

    % Close any old serial objects on this port
    old = instrfind("Port", port); %#ok<INSTRFND> (for very old MATLABs)
    if ~isempty(old)
        try, fclose(old); end %#ok<TRYNC>
        delete(old);
    end

    % --- Create serialport object (for newer MATLAB versions) ---
    % If you're on an older MATLAB (< R2019b), use serial()/fopen() instead.
    fprintf("Opening %s at %d baud...\n", port, baudRate);
    s = serialport(port, baudRate, "Timeout", 1);

    % Pico prints lines ending with \r\n; LF is enough as terminator
    configureTerminator(s, "LF");
    flush(s);  % clear any buffered junk

    % --- Figure & animated lines for live plot ---
    fig = figure('Name', 'ADXL372 Live Plot', ...
                 'NumberTitle', 'off', ...
                 'Color', 'w');
    ax = axes('Parent', fig);
    hold(ax, 'on');
    grid(ax, 'on');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Acceleration (g)');
    title(ax, sprintf('ADXL372 Live Acceleration (sensor %d)', SENSOR_ID));

    hAx = animatedline('Parent', ax);  % X
    hAy = animatedline('Parent', ax);  % Y
    hAz = animatedline('Parent', ax);  % Z
    legend(ax, {'Ax (g)', 'Ay (g)', 'Az (g)'}, 'Location', 'best');

    % Color them a bit
    set(hAx, 'Color', [0.85 0 0]);      % red-ish
    set(hAy, 'Color', [0 0.5 0.9]);     % blue-ish
    set(hAz, 'Color', [0.1 0.6 0.1]);   % green-ish

    % --- State variables ---
    t0 = [];   % first timestamp_us (for relative time)
    fprintf("Listening on %s... Close the figure to stop.\n", port);

    % --- Main read/plot loop ---
    try
        while isvalid(fig) && ishghandle(fig)
            % Read one line (blocks up to Timeout seconds)
            try
                line = readline(s);
            catch ME
                warning("Serial read error: %s", ME.message);
                break;
            end

            line = strtrim(line);
            if isempty(line)
                continue;
            end

            % Expect CSV: timestamp_us,sensor_id,x_raw,y_raw,z_raw
            parts = split(line, ',');
            if numel(parts) ~= 5
                % Might be banner text like "SingleAccelMonitor starting..."
                % Uncomment for debugging:
                % fprintf("Skipping: %s\n", line);
                continue;
            end

            % Parse numeric fields
            ts_us  = str2double(parts{1});
            sid    = str2double(parts{2});
            x_raw  = str2double(parts{3});
            y_raw  = str2double(parts{4});
            z_raw  = str2double(parts{5});

            if any(isnan([ts_us, sid, x_raw, y_raw, z_raw]))
                continue;  % malformed numeric line
            end
            if sid ~= SENSOR_ID
                continue;  % data from another sensor (for future multi-sensor)
            end

            % Establish t0 on first valid sample
            if isempty(t0)
                t0 = ts_us;
            end
            t_sec = (ts_us - t0) / 1e6;  % microseconds -> seconds

            % Convert to g
            ax_g = x_raw * LSB_TO_G;
            ay_g = y_raw * LSB_TO_G;
            az_g = z_raw * LSB_TO_G;

            % Append to animated lines
            addpoints(hAx, t_sec, ax_g);
            addpoints(hAy, t_sec, ay_g);
            addpoints(hAz, t_sec, az_g);

            % Update display (limitrate = nicer performance)
            drawnow limitrate;
        end
    catch ME
        warning("Live plot stopped due to error: %s", ME.message);
    end

    % --- Cleanup ---
    if exist('s','var') && ~isempty(s)
        try
            clear s;  % closes serialport
        catch
        end
    end
    if isvalid(fig)
        close(fig);
    end
    fprintf("Live plot stopped.\n");
end
