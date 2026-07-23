function human_bytes(value, number, unit_index) {
    split("B KiB MiB GiB TiB PiB", units, " ")
    number = value + 0
    unit_index = 1
    while (number >= 1024 && unit_index < 6) {
        number /= 1024
        unit_index++
    }
    if (unit_index == 1) return sprintf("%.0f %s", number, units[unit_index])
    return sprintf("%.2f %s", number, units[unit_index])
}

function terminal_safe_text(value) {
    gsub(/[^[:print:]]/, "?", value)
    return value
}

function repeat_text(text, count, output, repeat_index) {
    output = ""
    for (repeat_index = 0; repeat_index < count; repeat_index++) output = output text
    return output
}

function clip_text(text, width) {
    if (width <= 0) return ""
    if (length(text) <= width) return text
    if (width <= 2) return substr(text, 1, width)
    return substr(text, 1, width - 2) ".."
}

function pad_right(text, width) {
    text = clip_text(text, width)
    return text repeat_text(" ", width - length(text))
}

function left_right(left, right, width, gap) {
    if (width <= 0) return ""
    left = clip_text(left, width)
    right = clip_text(right, width)
    if (length(right) >= width) return right
    left = clip_text(left, width - length(right) - 1)
    gap = width - length(left) - length(right)
    return left repeat_text(" ", gap) right
}

function set_hit(type, uid, pid, command_index) {
    hit_type = type
    hit_uid = uid
    hit_pid = pid
    hit_command_index = command_index
}

function clear_hit() {
    hit_type = ""
    hit_uid = ""
    hit_pid = ""
    hit_command_index = ""
}

function record_screen_line() {
    screen_row++
    if (interactive_ui && hit_type != "" && hitmap_file != "") {
        printf "%d\t%s\t%s\t%s\t%s\t1\t%d\n", screen_row, hit_type,
            hit_uid, hit_pid, hit_command_index, ui_width >> hitmap_file
    }
}

function blank_line() {
    print ""
    record_screen_line()
}

function border(kind, left, fill, right) {
    if (kind == "top") {
        left = "╒"; fill = "═"; right = "╕"
    } else if (kind == "heavy") {
        left = "╞"; fill = "═"; right = "╡"
    } else if (kind == "bottom") {
        left = "╘"; fill = "═"; right = "╛"
    } else {
        left = "├"; fill = "─"; right = "┤"
    }
    printf "%s%s%s%s%s\n", color_border, left,
        repeat_text(fill, ui_width - 2), right, color_reset
    record_screen_line()
}

function box_line(text, color, visual_length, padding) {
    if (!visual_length) visual_length = length(text)
    if (visual_length > content_width) {
        text = clip_text(text, content_width)
        visual_length = content_width
    }
    padding = content_width - visual_length
    printf "%s│%s %s%s%s%s %s│%s\n", color_border, color_reset,
        color, text, color_reset, repeat_text(" ", padding),
        color_border, color_reset
    record_screen_line()
}

function bar_text(width, percent, filled) {
    filled = int((width * percent / 100.0) + 0.5)
    if (filled < 0) filled = 0
    if (filled > width) filled = width
    return repeat_text("█", filled) repeat_text(" ", width - filled)
}

function traffic_bar(label, value, color, width, text, percent, value_text) {
    percent = value * 100.0 / rate_ceiling
    if (percent > 100) percent = 100
    if (percent < 0) percent = 0
    if (value > rate_ceiling) value_text = "MAX"
    else if (value == rate_ceiling) value_text = rate_ceiling_label
    else value_text = human_bytes(value) "/s"
    width = content_width - 46
    if (width < 10) width = 10
    text = sprintf("%-8s [%s] %13s / %10s %6.1f%%", label,
        bar_text(width, percent), value_text, rate_ceiling_label, percent)
    box_line(text, color, content_width)
}

function init_braille(i, row0, row1, row2, row3, row4) {
    braille[0, 0] = " "
    split("⢀ ⢠ ⢰ ⢸", row0, " ")
    split("⡀ ⣀ ⣠ ⣰ ⣸", row1, " ")
    split("⡄ ⣄ ⣤ ⣴ ⣼", row2, " ")
    split("⡆ ⣆ ⣦ ⣶ ⣾", row3, " ")
    split("⡇ ⣇ ⣧ ⣷ ⣿", row4, " ")
    for (i = 1; i <= 4; i++) braille[0, i] = row0[i]
    for (i = 0; i <= 4; i++) {
        braille[1, i] = row1[i + 1]
        braille[2, i] = row2[i + 1]
        braille[3, i] = row3[i + 1]
        braille[4, i] = row4[i + 1]
    }
}

function history_peak(key, direction, width, count, start, sample_index, value, peak) {
    count = history_count[key] + 0
    start = count - (2 * width) + 1
    if (start < 1) start = 1
    peak = 0
    for (sample_index = start; sample_index <= count; sample_index++) {
        value = direction == 1 ? history_upload[key, sample_index] : \
            history_download[key, sample_index]
        if (value > peak) peak = value
    }
    return peak
}

function history_bound(key, direction, width, peak, bound) {
    peak = history_peak(key, direction, width)
    bound = 1.25 * peak
    if (bound < history_min_bound) bound = history_min_bound
    if (bound > rate_ceiling) bound = rate_ceiling
    return bound
}

function braille_level(value, present, bound, height, row, scaled, level, h) {
    if (!present || bound <= 0) return 0
    scaled = height * value / bound
    if (scaled > height) scaled = height
    if (scaled < 0.2) scaled = 0.2
    h = height - row
    level = int((5 * (scaled - h)) + 0.5)
    if (level < 0) level = 0
    if (level > 4) level = 4
    return level
}

function braille_graph_line(key, direction, width, height, row, count, capacity,
        start, visible, padding, column, left_slot, right_slot, left_index,
        right_index, left_present, right_present, left_value, right_value,
        left_level, right_level, bound, output) {
    if (width <= 0) return ""
    count = history_count[key] + 0
    capacity = 2 * width
    start = count - capacity + 1
    if (start < 1) start = 1
    visible = count - start + 1
    if (visible < 0) visible = 0
    padding = capacity - visible
    bound = history_bound(key, direction, width)
    output = ""
    for (column = 1; column <= width; column++) {
        left_slot = (2 * column) - 1 - padding
        right_slot = (2 * column) - padding
        left_present = left_slot > 0
        right_present = right_slot > 0
        left_index = start + left_slot - 1
        right_index = start + right_slot - 1
        left_value = left_present \
            ? (direction == 1 ? history_upload[key, left_index] : \
                history_download[key, left_index]) : 0
        right_value = right_present \
            ? (direction == 1 ? history_upload[key, right_index] : \
                history_download[key, right_index]) : 0
        left_level = braille_level(left_value, left_present, bound, height, row)
        right_level = braille_level(right_value, right_present, bound, height, row)
        output = output braille[left_level, right_level]
    }
    return output
}

function history_line(label, key, direction, color, prefix, suffix, width, peak,
        peak_text, sample_count) {
    prefix = sprintf("%-11s [", label)
    sample_count = history_count[key] + 0
    suffix = sprintf("] Peak %-13s %d/%d", "", sample_count, history_limit)
    width = content_width - length(prefix) - length(suffix)
    if (width < 10) width = 10
    peak = history_peak(key, direction, width)
    peak_text = clip_text(human_bytes(peak) "/s", 13)
    suffix = sprintf("] Peak %-13s %d/%d", peak_text, sample_count, history_limit)
    box_line(prefix braille_graph_line(key, direction, width, 1, 1) suffix,
        color, content_width)
}

function dual_history(key, width, upload_width, download_width) {
    upload_width = int((width - 1) / 2)
    download_width = width - upload_width - 1
    return braille_graph_line(key, 1, upload_width, 1, 1) "|" \
        braille_graph_line(key, 2, download_width, 1, 1)
}

function replace_at(text, position, replacement) {
    if (position < 1) position = 1
    if (position > length(text) - length(replacement) + 1) {
        position = length(text) - length(replacement) + 1
    }
    return substr(text, 1, position - 1) replacement \
        substr(text, position + length(replacement))
}

function duration_label(seconds) {
    if (seconds < 10) return sprintf("%.1fs", seconds)
    return sprintf("%ds", seconds)
}

function history_axis(width, seconds, left_label, middle_label, axis,
        middle_position) {
    seconds = 2 * width * refresh_interval
    left_label = duration_label(seconds)
    middle_label = duration_label(seconds / 2)
    axis = repeat_text("-", width)
    axis = replace_at(axis, 1, left_label)
    middle_position = int((width - length(middle_label)) / 2) + 1
    axis = replace_at(axis, middle_position, middle_label)
    axis = replace_at(axis, width - 2, "now")
    return axis
}

function pair_box(left, right, left_color, right_color, left_visual,
        right_visual, left_width, right_width, text) {
    left_width = int((content_width - 3) / 2)
    right_width = content_width - 3 - left_width
    if (left_visual > left_width) {
        left = clip_text(left, left_width)
        left_visual = left_width
    }
    if (right_visual > right_width) {
        right = clip_text(right, right_width)
        right_visual = right_width
    }
    left = left repeat_text(" ", left_width - left_visual)
    right = right repeat_text(" ", right_width - right_visual)
    text = left_color left color_reset " │ " right_color right color_reset
    box_line(text, "", content_width)
}

function print_history_pair(key, height, current_upload, current_download,
        show_axis, left_width, right_width, row, left, right, upload_peak,
        download_peak, header_left, header_right, graph_width) {
    left_width = int((content_width - 3) / 2)
    right_width = content_width - 3 - left_width
    graph_width = left_width
    upload_peak = history_peak(key, 1, graph_width)
    download_peak = history_peak(key, 2, graph_width)
    header_left = "UP " human_bytes(current_upload) "/s  MAX " \
        human_bytes(upload_peak) "/s"
    header_right = "DN " human_bytes(current_download) "/s  MAX " \
        human_bytes(download_peak) "/s"
    pair_box(header_left, header_right, color_upload, color_download,
        length(header_left), length(header_right))
    for (row = 1; row <= height; row++) {
        left = braille_graph_line(key, 1, graph_width, height, row)
        right = braille_graph_line(key, 2, graph_width, height, row)
        pair_box(left, right, color_upload, color_download, graph_width, graph_width)
    }
    if (show_axis) {
        left = history_axis(graph_width)
        right = history_axis(graph_width)
        pair_box(left, right, color_dim, color_dim, graph_width, graph_width)
    }
}

function print_history_single(key, direction, height, current, show_axis,
        label, color, row, peak, header_left, header_right) {
    peak = history_peak(key, direction, content_width)
    header_left = label " " human_bytes(current) "/s"
    header_right = "MAX " human_bytes(peak) "/s"
    box_line(left_right(header_left, header_right, content_width), color,
        content_width)
    for (row = 1; row <= height; row++) {
        box_line(braille_graph_line(key, direction, content_width, height, row),
            color, content_width)
    }
    if (show_axis) {
        box_line(history_axis(content_width), color_dim, content_width)
    }
}

function print_history_section(key, height, current_upload, current_download,
        show_axis) {
    if (two_column_layout) {
        print_history_pair(key, height, current_upload, current_download, show_axis)
    } else {
        print_history_single(key, 1, height, current_upload, show_axis,
            "UPLOAD", color_upload)
        print_history_single(key, 2, height, current_download, show_axis,
            "DOWNLOAD", color_download)
    }
}

function split_identity_row(label, uid, active) {
    return left_right(label, "UID " uid "  ACTIVE " active, content_width)
}

function compact_history_panel(key, direction, label, current, width,
        graph_width, value_text, graph, gap) {
    graph_width = int(width * 0.36)
    if (graph_width < 8) graph_width = 8
    value_text = label " " human_bytes(current) "/s"
    if (graph_width > width - length(value_text) - 1) {
        graph_width = width - length(value_text) - 1
    }
    if (graph_width < 1) return clip_text(value_text, width)
    graph = braille_graph_line(key, direction, graph_width, 1, 1)
    gap = width - length(value_text) - graph_width
    return value_text repeat_text(" ", gap) graph
}

function print_compact_history_pair(key, current_upload, current_download,
        left_width, right_width, left, right) {
    left_width = int((content_width - 3) / 2)
    right_width = content_width - 3 - left_width
    left = compact_history_panel(key, 1, "UPLOAD", current_upload, left_width)
    right = compact_history_panel(key, 2, "DOWNLOAD", current_download, right_width)
    pair_box(left, right, color_upload, color_download, left_width, right_width)
}

function history_section_rows(height, show_axis, rows_per_direction) {
    rows_per_direction = 1 + height + show_axis
    return two_column_layout ? rows_per_direction : 2 * rows_per_direction
}

function setup_table_columns(usable, remaining) {
    if (table_history_detail) {
        usable = content_width - 4
        user_width = int(usable * 0.32)
        uid_width = int(usable * 0.10)
        active_width = int(usable * 0.10)
        history_width = 0
    } else {
        usable = content_width - 5
        user_width = int(usable * 0.30)
        uid_width = int(usable * 0.08)
        active_width = int(usable * 0.08)
        history_width = int(usable * 0.20)
    }
    if (user_width < 20) user_width = 20
    if (uid_width < 5) uid_width = 5
    if (active_width < 6) active_width = 6
    if (!table_history_detail && history_width < 13) history_width = 13
    remaining = usable - user_width - uid_width - active_width - history_width
    upload_rate_width = int((remaining + 1) / 2)
    download_rate_width = remaining - upload_rate_width
}

function table_row(user_cell, uid_cell, upload_rate_cell,
        download_rate_cell, history_cell, active_cell) {
    user_cell = clip_text(user_cell, user_width)
    uid_cell = clip_text(uid_cell, uid_width)
    upload_rate_cell = clip_text(upload_rate_cell, upload_rate_width)
    download_rate_cell = clip_text(download_rate_cell, download_rate_width)
    active_cell = clip_text(active_cell, active_width)
    if (table_history_detail) {
        return sprintf("%-*s %*s %*s %*s %*s",
            user_width, user_cell, uid_width, uid_cell,
            upload_rate_width, upload_rate_cell,
            download_rate_width, download_rate_cell,
            active_width, active_cell)
    }
    return sprintf("%-*s %*s %*s %*s %s %*s",
        user_width, user_cell, uid_width, uid_cell,
        upload_rate_width, upload_rate_cell,
        download_rate_width, download_rate_cell,
        history_cell,
        active_width, active_cell)
}

function print_wrapped_command(uid, command_index, text, branch, continuation,
        available, chunk, first, command_color, metrics, cut_position,
        pid_label, first_prefix, metrics_left, metrics_right) {
    branch = (command_index == command_count[uid]) ? "  \\-- " : "  |-- "
    pid_label = "PID " command_pid[uid, command_index]
    first_prefix = branch pid_label "  "
    continuation = (command_index == command_count[uid]) ? "      " : "  |   "
    continuation = continuation repeat_text(" ", length(pid_label) + 2)
    available = content_width - length(first_prefix)
    command_color = (text == "[unattributed]") ? color_warning : ""
    first = 1
    while (length(text) > 0) {
        if (length(text) <= available) {
            chunk = text
            text = ""
        } else {
            chunk = substr(text, 1, available)
            cut_position = available
            while (cut_position > int(available / 2) &&
                    substr(chunk, cut_position, 1) != " ") cut_position--
            if (cut_position > int(available / 2)) {
                chunk = substr(text, 1, cut_position - 1)
                text = substr(text, cut_position + 1)
            } else {
                text = substr(text, available + 1)
            }
            sub(/^[[:space:]]+/, "", text)
        }
        box_line((first ? first_prefix : continuation) chunk, command_color)
        first = 0
    }
    metrics_left = sprintf("      UP %s  DN %s",
        human_bytes(command_upload_delta[uid, command_index] / elapsed) "/s",
        human_bytes(command_download_delta[uid, command_index] / elapsed) "/s")
    metrics_right = sprintf("ACTIVE %s", command_active[uid, command_index])
    metrics = left_right(metrics_left, metrics_right, content_width)
    box_line(metrics, color_dim)
}

function print_compact_command(uid, command_index, text, branch, pid_label,
        left, right, command_color) {
    branch = (command_index == command_count[uid]) ? "  \\-- " : "  |-- "
    pid_label = "PID " command_pid[uid, command_index]
    left = branch pid_label "  " text
    right = sprintf("UP %s  DN %s",
        human_bytes(command_upload_delta[uid, command_index] / elapsed) "/s",
        human_bytes(command_download_delta[uid, command_index] / elapsed) "/s")
    command_color = (text == "[unattributed]") ? color_warning : ""
    box_line(left_right(left, right, content_width), command_color)
}

function command_row_color(uid, command_index, default_color) {
    if (selected_uid != "" && uid == selected_uid &&
            command_pid[uid, command_index] == selected_pid) {
        return color_selected
    }
    return default_color
}

function print_fixed_compact_command(uid, command_index, text, branch, pid_label,
        left, right, command_color) {
    branch = (command_index == command_count[uid]) ? "\\--" : "|--"
    pid_label = "PID " command_pid[uid, command_index]
    left = sprintf("  [%d/%d] %s %s  %s", command_index, command_count[uid],
        branch, pid_label, text)
    right = sprintf("UP %s  DN %s",
        human_bytes(command_upload_delta[uid, command_index] / elapsed) "/s",
        human_bytes(command_download_delta[uid, command_index] / elapsed) "/s")
    command_color = (text == "[unattributed]") ? color_warning : ""
    command_color = command_row_color(uid, command_index, command_color)
    set_hit("command", uid, command_pid[uid, command_index], command_index)
    box_line(left_right(left, right, content_width), command_color)
    clear_hit()
}

function print_fixed_full_command(uid, command_index, text, branch, pid_label,
        left, metrics_left, metrics_right, command_color) {
    branch = (command_index == command_count[uid]) ? "\\--" : "|--"
    pid_label = "PID " command_pid[uid, command_index]
    left = sprintf("  [%d/%d] %s %s  %s", command_index, command_count[uid],
        branch, pid_label, text)
    command_color = (text == "[unattributed]") ? color_warning : ""
    command_color = command_row_color(uid, command_index, command_color)
    set_hit("command", uid, command_pid[uid, command_index], command_index)
    box_line(clip_text(left, content_width), command_color)
    metrics_left = sprintf("      UP %s  DN %s",
        human_bytes(command_upload_delta[uid, command_index] / elapsed) "/s",
        human_bytes(command_download_delta[uid, command_index] / elapsed) "/s")
    metrics_right = sprintf("ACTIVE %s", command_active[uid, command_index])
    box_line(left_right(metrics_left, metrics_right, content_width), command_color)
    clear_hit()
}

function print_command_placeholder(uid, detailed, slot, message) {
    set_hit("command_zone", uid, "", slot)
    message = slot == 1 ? "  No additional flowing commands in this interval." : ""
    box_line(message, color_dim)
    if (detailed) box_line("", color_dim)
    clear_hit()
}

function all_command_row_color(uid, command_index, default_color) {
    if (selected_uid != "" && uid == selected_uid &&
            all_command_pid[uid, command_index] == selected_pid) {
        return color_selected
    }
    return default_color
}

function print_all_compact_command(uid, command_index, text, branch, pid_label,
        left, right, command_color) {
    text = all_command_text[uid, command_index]
    branch = (command_index == all_command_count[uid]) ? "\\--" : "|--"
    pid_label = "PID " all_command_pid[uid, command_index]
    left = sprintf("  [%d/%d] %s %s  %s", command_index, all_command_count[uid],
        branch, pid_label, text)
    right = sprintf("UP %s  DN %s",
        human_bytes(all_command_upload_delta[uid, command_index] / elapsed) "/s",
        human_bytes(all_command_download_delta[uid, command_index] / elapsed) "/s")
    command_color = (text == "[unattributed]") ? color_warning : ""
    command_color = all_command_row_color(uid, command_index, command_color)
    set_hit("command", uid, all_command_pid[uid, command_index], command_index)
    box_line(left_right(left, right, content_width), command_color)
    clear_hit()
}

function print_all_full_command(uid, command_index, text, branch, pid_label,
        left, metrics_left, metrics_right, command_color) {
    text = all_command_text[uid, command_index]
    branch = (command_index == all_command_count[uid]) ? "\\--" : "|--"
    pid_label = "PID " all_command_pid[uid, command_index]
    left = sprintf("  [%d/%d] %s %s  %s", command_index, all_command_count[uid],
        branch, pid_label, text)
    command_color = (text == "[unattributed]") ? color_warning : ""
    command_color = all_command_row_color(uid, command_index, command_color)
    set_hit("command", uid, all_command_pid[uid, command_index], command_index)
    box_line(clip_text(left, content_width), command_color)
    metrics_left = sprintf("      UP %s  DN %s",
        human_bytes(all_command_upload_delta[uid, command_index] / elapsed) "/s",
        human_bytes(all_command_download_delta[uid, command_index] / elapsed) "/s")
    metrics_right = sprintf("ACTIVE %s", all_command_active[uid, command_index])
    box_line(left_right(metrics_left, metrics_right, content_width), command_color)
    clear_hit()
}

function wrapped_command_rows(uid, command_index, text, pid_label, available,
        cut_position, chunk, rows) {
    text = command_text[uid, command_index]
    pid_label = "PID " command_pid[uid, command_index]
    available = content_width - length("  |-- " pid_label "  ")
    rows = 1
    while (length(text) > 0) {
        rows++
        if (length(text) <= available) break
        chunk = substr(text, 1, available)
        cut_position = available
        while (cut_position > int(available / 2) &&
                substr(chunk, cut_position, 1) != " ") cut_position--
        if (cut_position > int(available / 2)) {
            text = substr(text, cut_position + 1)
        } else {
            text = substr(text, available + 1)
        }
        sub(/^[[:space:]]+/, "", text)
    }
    return rows
}

function print_small_line(text) {
    if (ui_width <= 0) return
    print clip_text(text, ui_width)
    record_screen_line()
}

function print_small_terminal_message() {
    print_small_line("netwtop: terminal too small.")
    print_small_line(sprintf("Size: %dx%d; need at least 78x20.", ui_width, ui_height))
    print_small_line("Resize the terminal or press q to quit.")
}

FILENAME == ARGV[1] {
    names[$1] = terminal_safe_text($2)
    next
}

FILENAME == ARGV[2] {
    uid = $1
    display_command = terminal_safe_text($3)
    if ($3 != "[unattributed]") attributed_active += $8
    else unattributed_active += $8
    all_command_index = ++all_command_count[uid]
    all_command_pid[uid, all_command_index] = $2
    all_command_text[uid, all_command_index] = display_command
    all_command_upload_delta[uid, all_command_index] = $4
    all_command_download_delta[uid, all_command_index] = $5
    all_command_active[uid, all_command_index] = $8
    if (($4 + $5) <= 0) next
    command_index = ++command_count[uid]
    command_pid[uid, command_index] = $2
    command_text[uid, command_index] = display_command
    command_upload_delta[uid, command_index] = $4
    command_download_delta[uid, command_index] = $5
    command_active[uid, command_index] = $8
    flowing_command_count++
    next
}

FILENAME == ARGV[3] {
    uid = $1
    user_index = ++user_count
    user_uid[user_index] = uid
    user_name[user_index] = (uid in names) ? names[uid] : "uid-" uid
    user_upload_delta[user_index] = $2
    user_download_delta[user_index] = $3
    user_active[user_index] = $6
    upload_delta_total += $2
    download_delta_total += $3
    active_total += $6
    next
}

FILENAME == ARGV[4] {
    history_key = $2
    history_index = ++history_count[history_key]
    history_upload[history_key, history_index] = $3 + 0
    history_download[history_key, history_index] = $4 + 0
    next
}

END {
    if (ui_width < 78 || (ui_height > 0 && ui_height < 20)) {
        print_small_terminal_message()
        exit
    }

    content_width = ui_width - 4
    display_time = terminal_safe_text(display_time)
    host_name = terminal_safe_text(host_name)
    interface_name = terminal_safe_text(interface_name)
    backend = terminal_safe_text(backend)
    scope = terminal_safe_text(scope)
    session_label = terminal_safe_text(session_label)
    column_breakpoint = int(two_column_width + 0)
    if (column_breakpoint < 1) column_breakpoint = 100
    two_column_layout = ui_width >= column_breakpoint
    rate_ceiling = 128 * 1024 * 1024
    rate_ceiling_label = "128 MiB/s"
    history_min_bound = 64 * 1024
    init_braille()
    detailed_top_rows = two_column_layout ? 17 : 23
    detailed_user_rows = 1 + history_section_rows(2, 0)
    detailed_footer_rows = 3 + history_section_rows(2, 0)
    compact_user_rows = two_column_layout ? 2 : 1
    compact_footer_rows = two_column_layout ? 4 : 3
    detailed_compact_base_height = detailed_top_rows + 4 + \
        (detailed_user_rows * user_count) + detailed_footer_rows + \
        (user_count ? 0 : 1)
    detailed_full_base_height = detailed_compact_base_height + \
        (user_count > 1 ? user_count - 1 : 0)
    full_command_rows = 0
    for (user_index = 1; user_index <= user_count; user_index++) {
        uid = user_uid[user_index]
        for (command_index = 1; command_index <= command_count[uid]; command_index++) {
            full_command_rows += wrapped_command_rows(uid, command_index)
        }
    }
    full_required_height = detailed_full_base_height + full_command_rows
    effective_mode = display_mode
    history_detail = 0
    if (interactive_ui) {
        interactive_full_min_height = detailed_top_rows + 4 + \
            detailed_user_rows + (2 * command_view_size) + detailed_footer_rows
        if (display_mode == "full" || display_mode == "auto") {
            history_detail = ui_height <= 0 || ui_height >= interactive_full_min_height
            if (display_mode == "auto" && history_detail && ui_height > 0) {
                interactive_column_count = 1
                compact_user_block_rows = compact_user_rows + command_view_size
                compact_user_groups = user_count > 0 \
                    ? int((user_count + interactive_column_count - 1) / \
                        interactive_column_count) : 0
                compact_all_user_rows = compact_user_groups > 0 \
                    ? compact_user_groups * compact_user_block_rows : 1
                detailed_panels_compact_users_height = detailed_top_rows + 4 + \
                    compact_all_user_rows + detailed_footer_rows
                if (ui_height < detailed_panels_compact_users_height) {
                    history_detail = 0
                }
            }
            effective_mode = history_detail ? "full" : "compact"
        }
    } else {
        if (display_mode == "full") {
            history_detail = ui_height <= 0 || ui_height >= detailed_compact_base_height
            effective_mode = (ui_height <= 0 || \
                (history_detail && ui_height >= full_required_height)) ? "full" : "compact"
        }
        if (display_mode == "auto") {
            history_detail = ui_height <= 0 || ui_height >= detailed_compact_base_height
            effective_mode = (ui_height <= 0 || \
                (history_detail && ui_height >= full_required_height)) ? "full" : "compact"
        }
    }
    table_history_detail = history_detail
    setup_table_columns()

    attribution_total = attributed_active + unattributed_active
    attribution_percent = attribution_total > 0 \
        ? attributed_active * 100.0 / attribution_total : 100
    upload_coverage = interface_tx_delta > 0 \
        ? upload_delta_total * 100.0 / interface_tx_delta : 0
    download_coverage = interface_rx_delta > 0 \
        ? download_delta_total * 100.0 / interface_rx_delta : 0
    upload_coverage_text = interface_tx_delta > 0 \
        ? sprintf("%.1f%%", upload_coverage) : "n/a"
    download_coverage_text = interface_rx_delta > 0 \
        ? sprintf("%.1f%%", download_coverage) : "n/a"
    status_left = "Users: " (user_count + 0) "  Commands: " (flowing_command_count + 0) \
        "  PID: " sprintf("%.1f%%", attribution_percent)
    if (attribution_device_scoped) {
        status_right = "Accounted: UP " upload_coverage_text \
            "  DN " download_coverage_text
    } else {
        status_right = "App detail: all interfaces"
    }

    border("top")
    box_line(left_right("NETWTOP  NETWORK TRAFFIC MONITOR", display_time,
        content_width), color_title)
    box_line(left_right("Host: " host_name "  Device: " interface_name,
        backend "  Refresh: " refresh_interval "s", content_width), color_dim)
    if (history_detail) box_line("Scope: " scope, "")
    border("heavy")
    traffic_bar("UPLOAD", interface_tx_delta / elapsed, color_upload)
    traffic_bar("DOWNLOAD", interface_rx_delta / elapsed, color_download)
    if (history_detail) {
        print_history_section("I", 4, interface_tx_delta / elapsed,
            interface_rx_delta / elapsed, 1)
        border("thin")
    } else if (two_column_layout) {
        print_history_pair("I", 1, interface_tx_delta / elapsed,
            interface_rx_delta / elapsed, 0)
    } else {
        history_line("UP HISTORY", "I", 1, color_upload)
        history_line("DN HISTORY", "I", 2, color_download)
    }
    box_line(left_right(status_left, status_right, content_width), "")
    border("bottom")
    blank_line()

    for (user_index = 1; user_index <= user_count; user_index++) {
        user_rank[user_index] = 1
        user_traffic = user_upload_delta[user_index] + user_download_delta[user_index]
        for (other_index = 1; other_index <= user_count; other_index++) {
            other_traffic = user_upload_delta[other_index] + user_download_delta[other_index]
            if (other_traffic > user_traffic ||
                    (other_traffic == user_traffic && other_index < user_index)) {
                user_rank[user_index]++
            }
        }
    }

    if (interactive_ui) {
        expanded_user_index = 0
        for (user_index = 1; user_index <= user_count; user_index++) {
            if (expanded_uid != "" && user_uid[user_index] == expanded_uid) {
                expanded_user_index = user_index
            }
        }
        if (layout_state_file != "") {
            printf "expanded\t%s\n", expanded_user_index ? expanded_uid : "-" \
                > layout_state_file
        }

        if (expanded_user_index) {
            footer_rows = history_detail ? detailed_footer_rows : compact_footer_rows
            command_entry_rows = history_detail ? 2 : 1
            body_available = ui_height - screen_row - 4 - footer_rows
            fixed_user_rows = history_detail ? detailed_user_rows : compact_user_rows
            expanded_command_slots = int((body_available - fixed_user_rows) / \
                command_entry_rows)
            if (expanded_command_slots < 1) expanded_command_slots = 1
            uid = user_uid[expanded_user_index]
            expanded_command_offset = int(command_scroll_offset + 0)
            max_command_offset = all_command_count[uid] > expanded_command_slots \
                ? all_command_count[uid] - expanded_command_slots : 0
            if (expanded_command_offset < 0) expanded_command_offset = 0
            if (expanded_command_offset > max_command_offset) {
                expanded_command_offset = max_command_offset
            }
            expanded_command_start = all_command_count[uid] > 0 \
                ? expanded_command_offset + 1 : 0
            expanded_command_end = expanded_command_offset + expanded_command_slots
            if (expanded_command_end > all_command_count[uid]) {
                expanded_command_end = all_command_count[uid]
            }
            table_page_size = expanded_command_slots
            if (layout_state_file != "") {
                printf "table\t0\t%d\n", table_page_size >> layout_state_file
                printf "command\t%s\t%d\n", uid, expanded_command_offset \
                    >> layout_state_file
            }

            username = user_name[expanded_user_index]
            focus_label = sprintf("CHECKED  Commands %d-%d/%d  %s",
                expanded_command_start, expanded_command_end,
                all_command_count[uid] + 0, username)
            border("top")
            box_line(left_right(focus_label, session_label, content_width), color_title)
            if (two_column_layout) {
                box_line(left_right("RANK USER", "UID / ACTIVE", content_width),
                    color_header, content_width)
            } else {
                box_line(table_row("RANK USER", "UID", "UPLOAD/s", "DOWNLOAD/s",
                    history_detail ? "" : pad_right("HISTORY UP|DN", history_width),
                    "ACTIVE"), color_header, content_width)
            }
            border("heavy")

            user_label = sprintf("[x] [%d/%d] %s", user_rank[expanded_user_index],
                user_count, username)
            set_hit("user", uid, "", 0)
            if (two_column_layout) {
                user_line = split_identity_row(user_label, uid,
                    user_active[expanded_user_index])
            } else {
                user_line = table_row(user_label, uid,
                    human_bytes(user_upload_delta[expanded_user_index] / elapsed) "/s",
                    human_bytes(user_download_delta[expanded_user_index] / elapsed) "/s",
                    dual_history("U:" uid, history_width),
                    user_active[expanded_user_index])
            }
            box_line(user_line, selected_pid == "" ? color_selected : color_user,
                content_width)
            clear_hit()
            if (history_detail) {
                print_history_section("U:" uid, 2,
                    user_upload_delta[expanded_user_index] / elapsed,
                    user_download_delta[expanded_user_index] / elapsed, 0)
            } else if (two_column_layout) {
                print_compact_history_pair("U:" uid,
                    user_upload_delta[expanded_user_index] / elapsed,
                    user_download_delta[expanded_user_index] / elapsed)
            }
            for (command_slot = 1; command_slot <= expanded_command_slots; command_slot++) {
                command_index = expanded_command_offset + command_slot
                if (command_index <= all_command_count[uid]) {
                    if (history_detail) print_all_full_command(uid, command_index)
                    else print_all_compact_command(uid, command_index)
                } else {
                    print_command_placeholder(uid, history_detail, command_slot)
                }
            }
            border("heavy")
            if (two_column_layout) {
                total_line = split_identity_row("ACCOUNTED", "-", active_total + 0)
            } else {
                total_line = table_row("ACCOUNTED", "-",
                    human_bytes(upload_delta_total / elapsed) "/s",
                    human_bytes(download_delta_total / elapsed) "/s",
                    dual_history("A", history_width), active_total + 0)
            }
            box_line(total_line, color_total, content_width)
            if (history_detail) {
                print_history_section("A", 2, upload_delta_total / elapsed,
                    download_delta_total / elapsed, 0)
            } else if (two_column_layout) {
                print_compact_history_pair("A", upload_delta_total / elapsed,
                    download_delta_total / elapsed)
            }
            border("bottom")
        } else {
        footer_rows = history_detail ? detailed_footer_rows : compact_footer_rows
        table_column_count = 1
        body_available = ui_height - screen_row - 4 - footer_rows
        user_history_detail = history_detail
        if (display_mode == "auto" && user_history_detail && user_count > 0 &&
                ui_height > 0) {
            detailed_user_groups = int((user_count + table_column_count - 1) / \
                table_column_count)
            detailed_user_block_rows = detailed_user_rows + \
                (2 * command_view_size)
            detailed_all_user_rows = detailed_user_groups * detailed_user_block_rows + \
                (detailed_user_groups > 1 ? detailed_user_groups - 1 : 0)
            if (body_available < detailed_all_user_rows) user_history_detail = 0
        }
        table_history_detail = user_history_detail
        setup_table_columns()
        command_entry_rows = user_history_detail ? 2 : 1
        user_block_rows = (user_history_detail ? detailed_user_rows : compact_user_rows) + \
            (command_view_size * command_entry_rows)
        if (ui_height <= 0) {
            visible_user_capacity = user_count
        } else {
            if (body_available < user_block_rows) {
                visible_user_capacity = 0
            } else if (user_history_detail) {
                visible_user_groups = 1 + int((body_available - user_block_rows) / \
                    (user_block_rows + 1))
                visible_user_capacity = visible_user_groups * table_column_count
            } else {
                visible_user_groups = int(body_available / user_block_rows)
                visible_user_capacity = visible_user_groups * table_column_count
            }
            if (visible_user_capacity > user_count) visible_user_capacity = user_count
        }
        table_page_size = visible_user_capacity > 0 ? visible_user_capacity : 1
        max_table_scroll = visible_user_capacity > 0 && user_count > visible_user_capacity \
            ? user_count - visible_user_capacity : 0
        actual_table_scroll = int(table_scroll + 0)
        if (actual_table_scroll < 0) actual_table_scroll = 0
        if (actual_table_scroll > max_table_scroll) actual_table_scroll = max_table_scroll
        visible_start = visible_user_capacity > 0 ? actual_table_scroll + 1 : 0
        visible_end = visible_user_capacity > 0 \
            ? actual_table_scroll + visible_user_capacity : 0
        if (visible_end > user_count) visible_end = user_count
        viewport_label = user_count > 0 \
            ? sprintf("Users %d-%d/%d", visible_start, visible_end, user_count) : "Users 0/0"
        if (layout_state_file != "") {
            printf "table\t%d\t%d\n", actual_table_scroll, table_page_size \
                >> layout_state_file
        }

        border("top")
        box_line(left_right("NETWORK USAGE BY USER  " viewport_label,
            session_label, content_width), color_title)
        if (two_column_layout) {
            box_line(left_right("RANK USER", "UID / ACTIVE", content_width),
                color_header, content_width)
        } else {
            box_line(table_row("RANK USER", "UID", "UPLOAD/s", "DOWNLOAD/s",
                user_history_detail ? "" : pad_right("HISTORY UP|DN", history_width),
                "ACTIVE"), color_header, content_width)
        }
        border("heavy")

        if (visible_user_capacity == 0 && user_count > 0) {
            box_line("No room for a complete user block; enlarge the terminal.", color_warning)
        } else {
            displayed_user_number = 0
            for (user_index = visible_start; user_index <= visible_end; user_index++) {
                if (user_history_detail && displayed_user_number > 0) border("thin")
                displayed_user_number++
                uid = user_uid[user_index]
                username = user_name[user_index]
                user_label = sprintf("[ ] [%d/%d] %s", user_rank[user_index], user_count,
                    username)
                set_hit("user", uid, "", 0)
                user_color = selected_uid != "" && uid == selected_uid && selected_pid == "" \
                    ? color_selected : color_user
                if (two_column_layout) {
                    user_line = split_identity_row(user_label, uid,
                        user_active[user_index])
                } else {
                    user_line = table_row(user_label, uid,
                        human_bytes(user_upload_delta[user_index] / elapsed) "/s",
                        human_bytes(user_download_delta[user_index] / elapsed) "/s",
                        dual_history("U:" uid, history_width), user_active[user_index])
                }
                box_line(user_line, user_color, content_width)
                clear_hit()
                if (user_history_detail) {
                    print_history_section("U:" uid, 2,
                        user_upload_delta[user_index] / elapsed,
                        user_download_delta[user_index] / elapsed, 0)
                } else if (two_column_layout) {
                    print_compact_history_pair("U:" uid,
                        user_upload_delta[user_index] / elapsed,
                        user_download_delta[user_index] / elapsed)
                }

                user_command_offset = command_scroll_uid != "" && uid == command_scroll_uid \
                    ? int(command_scroll_offset + 0) : 0
                max_command_offset = command_count[uid] > command_view_size \
                    ? command_count[uid] - command_view_size : 0
                if (user_command_offset < 0) user_command_offset = 0
                if (user_command_offset > max_command_offset) {
                    user_command_offset = max_command_offset
                }
                if (command_scroll_uid != "" && uid == command_scroll_uid &&
                        layout_state_file != "") {
                    printf "command\t%s\t%d\n", uid, user_command_offset \
                        >> layout_state_file
                }
                for (command_slot = 1; command_slot <= command_view_size; command_slot++) {
                    command_index = user_command_offset + command_slot
                    if (command_index <= command_count[uid]) {
                        if (user_history_detail) {
                            print_fixed_full_command(uid, command_index,
                                command_text[uid, command_index])
                        } else {
                            print_fixed_compact_command(uid, command_index,
                                command_text[uid, command_index])
                        }
                    } else {
                        print_command_placeholder(uid, user_history_detail, command_slot)
                    }
                }
            }
        }
        if (!user_count) box_line("No attributable application traffic.", color_dim)
        border("heavy")
        if (two_column_layout) {
            total_line = split_identity_row("ACCOUNTED", "-", active_total + 0)
        } else {
            total_line = table_row("ACCOUNTED", "-",
                human_bytes(upload_delta_total / elapsed) "/s",
                human_bytes(download_delta_total / elapsed) "/s",
                dual_history("A", history_width), active_total + 0)
        }
        box_line(total_line, color_total, content_width)
        if (history_detail) {
            print_history_section("A", 2, upload_delta_total / elapsed,
                download_delta_total / elapsed, 0)
        } else if (two_column_layout) {
            print_compact_history_pair("A", upload_delta_total / elapsed,
                download_delta_total / elapsed)
        }
        border("bottom")
        }
    } else {
        border("top")
        box_line(left_right("NETWORK USAGE BY USER", session_label, content_width), color_title)
        if (two_column_layout) {
            box_line(left_right("RANK USER", "UID / ACTIVE", content_width),
                color_header, content_width)
        } else {
            box_line(table_row("RANK USER", "UID", "UPLOAD/s", "DOWNLOAD/s",
                history_detail ? "" : pad_right("HISTORY UP|DN", history_width),
                "ACTIVE"), color_header, content_width)
        }
        border("heavy")

        if (effective_mode == "compact") {
            if (ui_height <= 0) {
                command_space = flowing_command_count
                command_budget = flowing_command_count
            } else {
                base_rows = 18 + user_count + (user_count ? 0 : 1)
                if (two_column_layout) base_rows += user_count + 1
                if (history_detail) base_rows = detailed_compact_base_height
                command_space = ui_height - base_rows
                if (command_space < 0) command_space = 0
                command_budget = command_space
                if (flowing_command_count > command_space && command_budget > 0) command_budget--
            }
        }

        for (user_index = 1; user_index <= user_count; user_index++) {
            if (effective_mode != "compact" && user_index > 1) border("thin")
            uid = user_uid[user_index]
            username = user_name[user_index]
            user_label = sprintf("[%d/%d] %s", user_rank[user_index], user_count, username)
            if (two_column_layout) {
                user_line = split_identity_row(user_label, uid, user_active[user_index])
            } else {
                user_line = table_row(user_label, uid,
                    human_bytes(user_upload_delta[user_index] / elapsed) "/s",
                    human_bytes(user_download_delta[user_index] / elapsed) "/s",
                    dual_history("U:" uid, history_width), user_active[user_index])
            }
            box_line(user_line, color_user, content_width)
            if (history_detail) {
                print_history_section("U:" uid, 2,
                    user_upload_delta[user_index] / elapsed,
                    user_download_delta[user_index] / elapsed, 0)
            } else if (two_column_layout) {
                print_compact_history_pair("U:" uid,
                    user_upload_delta[user_index] / elapsed,
                    user_download_delta[user_index] / elapsed)
            }
            for (command_index = 1; command_index <= command_count[uid]; command_index++) {
                if (effective_mode == "compact") {
                    if (displayed_commands < command_budget) {
                        print_compact_command(uid, command_index, command_text[uid, command_index])
                        displayed_commands++
                    }
                } else {
                    print_wrapped_command(uid, command_index, command_text[uid, command_index])
                }
            }
        }

        if (!user_count) box_line("No attributable application traffic.", color_dim)
        if (effective_mode == "compact" && flowing_command_count > displayed_commands && command_space > 0) {
            hidden_commands = flowing_command_count - displayed_commands
            box_line(sprintf("... %d more flowing command%s hidden; enlarge the terminal or press f.",
                hidden_commands, hidden_commands == 1 ? "" : "s"), color_dim)
        }
        border("heavy")
        if (two_column_layout) {
            total_line = split_identity_row("ACCOUNTED", "-", active_total + 0)
        } else {
            total_line = table_row("ACCOUNTED", "-",
                human_bytes(upload_delta_total / elapsed) "/s",
                human_bytes(download_delta_total / elapsed) "/s",
                dual_history("A", history_width), active_total + 0)
        }
        box_line(total_line, color_total, content_width)
        if (history_detail) {
            print_history_section("A", 2, upload_delta_total / elapsed,
                download_delta_total / elapsed, 0)
        } else if (two_column_layout) {
            print_compact_history_pair("A", upload_delta_total / elapsed,
                download_delta_total / elapsed)
        }
        border("bottom")
    }
}
