import os
import json
import tkinter as tk
from tkinter import ttk, messagebox
from ttkbootstrap import Style
from PIL import Image, ImageTk
import random
import tkinter.font as tkFont
from datetime import date, datetime
import calendar
import sys
from pathlib import Path

# APP ROOT
if getattr(sys, 'frozen', False):
    APP_ROOT = Path(sys.executable).parent
else:
    APP_ROOT = Path(__file__).parent

config_dirty = False
CONFIG_FILE = APP_ROOT / "JSON" / "commands_edit.json"
DEFAULT_CONFIG_FILE = APP_ROOT / "JSON" / "commands_default.json"
ICON_PATH = APP_ROOT / "media" / "commands.ico"
MAX_ROWS = 35

# --- Global state ---
previous_selected_index = None
current_command_key = None
row_widgets = []

# --- Helper Functions ---
def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)
        
# --- Tooltip Class ---
class Tooltip:
    def __init__(self, widget):
        self.widget = widget
        self.tipwindow = None
        self.text = ""
        widget.bind("<Enter>", self.show)
        widget.bind("<Leave>", self.hide)

    def set_text(self, text):
        self.text = text

    def show(self, event=None):
        if self.tipwindow or not self.text:
            return
        x = self.widget.winfo_rootx() + 20
        y = self.widget.winfo_rooty() + 20
        self.tipwindow = tw = tk.Toplevel(self.widget)
        tw.wm_overrideredirect(True)
        tw.wm_geometry(f"+{x}+{y}")
        label = tk.Label(tw, text=self.text, justify="left",
                         background="#FFFFE0", relief="solid", borderwidth=1,
                         font=("Segoe UI", 13))
        label.pack(ipadx=5, ipady=2)

    def hide(self, event=None):
        if self.tipwindow:
            self.tipwindow.destroy()
        self.tipwindow = None
         
# --- Save Config ---
def save_config():
    global config_dirty

    cmd_key = current_command_key
    cmd_data = config["AutoCommands"][cmd_key]

    # Reset arrays
    cmd_data["Times"] = []
    cmd_data["RepeatIntervalMinutes"] = []
    cmd_data["Type"] = []
    cmd_data["Day"] = []
    cmd_data["Mode"] = []

    for widgets in row_widgets:
        frame, t_vars, r_var, type_var, date_vars, mode_var = widgets

        # --- Time ---
        h, m, s = [v.get() for v in t_vars]
        time_str = f"{int(h):02d}:{int(m):02d}:{int(s):02d}"

        # --- Date ---
        y, mo, d = [v.get() for v in date_vars]
        date_str = f"{int(y):04d}-{int(mo):02d}-{int(d):02d}"

        cmd_data["Times"].append(time_str)
        cmd_data["RepeatIntervalMinutes"].append(int(r_var.get()))
        cmd_data["Type"].append(type_var.get())

        # Day applies only if daily + fixed mode
        if type_var.get() == "daily" and mode_var.get() == "fixed":
            cmd_data["Day"].append(date_str)
        else:
            cmd_data["Day"].append("")

        # Mode
        cmd_data["Mode"].append(mode_var.get())

    # Save file
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2, separators=(',', ': '))

    messagebox.showinfo("Saved", f"Config saved for {cmd_key}")
    config_dirty = False
    save_btn.config(state="disabled")
    
# --- Global Save ---
def save_all_config():
    global config_dirty

    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2, separators=(',', ': '))

    config_dirty = False
    save_btn.config(state="disabled")

    show_status_message("✔ Global configuration saved", "success", 3000)
    
# --- List Table ---
def open_autocommands_table():
    table_win = tk.Toplevel(root)
    table_win.title("Auto Commands Overview (Read Only)")
    table_win.geometry("1500x800")
    table_win.configure(bg="#1E1E1E")

    columns = ["Command", "Row", "Time", "Repeat", "Type", "Mode", "Day"]

    style = ttk.Style(table_win)

    # --- Treeview FIRST (no style yet) ---
    tree = ttk.Treeview(
        table_win,
        columns=columns,
        show="headings"
    )
    tree.pack(fill="both", expand=True, padx=10, pady=10)

    # --- Apply style AFTER widget is mapped (FIX) ---
    def apply_tree_style():
        style.configure(
            "Treeview",
            font=("Segoe UI", 15),
            rowheight=42,
            background="#1E1E1E",
            fieldbackground="#1E1E1E",
            foreground="#E0E0E0"
        )
        style.configure(
            "Treeview.Heading",
            font=("Segoe UI", 17, "bold"),
            foreground="#FFD700",
            background="#1E1E1E"
        )

    table_win.after_idle(apply_tree_style)

    # --- Columns ---
    for col in columns:
        tree.heading(col, text=col)
        tree.column(col, anchor="center", width=180)

    from datetime import datetime

    # --- Populate table ---
    for cmd_index, (cmd_name, cmd_data) in enumerate(config["AutoCommands"].items()):

        times = cmd_data.get("Times", [])
        repeats = cmd_data.get("RepeatIntervalMinutes", [])
        types = cmd_data.get("Type", [])
        days = cmd_data.get("Day", [])
        modes = cmd_data.get("Mode", [])

        if not times:
            # Ако командата нема редови, внеси No Data
            tag_no_data = f"{cmd_name}_nodata"
            tree.insert(
                "",
                "end",
                values=(cmd_name.lstrip("/"), "-", "No Data", "-", "-", "-", "-"),
                tags=(tag_no_data,)
            )
            tree.tag_configure(tag_no_data, background="#2D2D30", foreground="#CFCFCF")
        else:
            for i in range(len(times)):
                time_val = times[i]
                repeat_val = repeats[i] if i < len(repeats) else "-"
                type_val = types[i] if i < len(types) else "-"
                day_val = days[i] if i < len(days) else ""
                mode_val = modes[i] if i < len(modes) else "loop"

                # --- Past check ---
                is_past = False
                if mode_val == "fixed" and day_val:
                    try:
                        d = datetime.strptime(day_val, "%Y-%m-%d").date()
                        h, m, s = map(int, time_val.split(":"))
                        dt = datetime(d.year, d.month, d.day, h, m, s)
                        if dt < datetime.now():
                            is_past = True
                    except:
                        pass

                # --- Colors (clean & readable) ---
                if is_past:
                    bg, fg = "#8B0000", "#FFFFFF"     # dark red
                elif mode_val == "fixed":
                    bg, fg = "#2E8B57", "#FFFFFF"     # dark green
                else:
                    bg, fg = "#2D2D30", "#CFCFCF"     # neutral loop

                tag = f"{cmd_name}_{i}"
                tree.tag_configure(tag, background=bg, foreground=fg)

                tree.insert(
                    "",
                    "end",
                    values=(
                        cmd_name.lstrip("/"),
                        i + 1,
                        time_val,
                        repeat_val,
                        type_val,
                        mode_val,
                        day_val if day_val else "-"
                    ),
                    tags=(tag,)
                )

        # spacer between commands
        tree.insert("", "end", values=("", "", "", "", "", "", ""), tags=(f"spacer_{cmd_index}",))
        tree.tag_configure(f"spacer_{cmd_index}", background="#1E1E1E")

# --- Reset to Default ---
def reset_to_default():
    global config, row_widgets, config_dirty

    if current_command_key is None:
        return

    answer = messagebox.askyesno(
        "Reset to Default",
        "Are you sure?\nOnly the selected command will be reset."
    )
    if not answer:
        return

    if not os.path.exists(DEFAULT_CONFIG_FILE):
        messagebox.showerror(
            "Missing default file",
            f"commands_default.json not found!\nPath:\n{DEFAULT_CONFIG_FILE}"
        )
        return

    with open(DEFAULT_CONFIG_FILE, "r") as f:
        default_config = json.load(f)

    # 🔁 Reset only selected command
    config["AutoCommands"][current_command_key] = \
        default_config["AutoCommands"][current_command_key]

    cmd_data = config["AutoCommands"][current_command_key]

    # --- Ensure Mode exists and set all to loop ---
    if "Mode" not in cmd_data:
        cmd_data["Mode"] = []

    for i in range(len(cmd_data["Times"])):
        if i >= len(cmd_data["Mode"]):
            cmd_data["Mode"].append("loop")
        else:
            cmd_data["Mode"][i] = "loop"

    # --- Refresh UI ---
    for widget in rows_frame.winfo_children():
        widget.destroy()
    row_widgets.clear()
    on_frame_configure(None)

    for idx in range(len(cmd_data["Times"])):
        add_row(cmd_data, idx)

    # 🔥 AUTO SAVE
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2, separators=(',', ': '))

    config_dirty = False
    save_btn.config(state="disabled")

    show_status_message(
        "↺ Command reset to default & auto-saved",
        "success",
        3000
    )

# --- Mark Dirty ---  
def mark_dirty(*args):
    global config_dirty
    config_dirty = True
    save_btn.config(state="normal")

# --- Reset JSON File ---  
def reset_all_autocommands():
    global config, row_widgets, config_dirty
    global current_command_key, previous_selected_command

    answer = messagebox.askyesno(
        "RESET ALL COMMANDS",
        "⚠️ This will ERASE ALL AutoCommands data!\n\n"
        "All Times, Repeat, Type, Mode and Day values\n"
        "will be cleared for EVERY command.\n\n"
        "Do you want to continue?"
    )

    if not answer:
        return

    # 🔥 Clear ALL AutoCommands data
    for cmd_key, cmd_data in config["AutoCommands"].items():
        cmd_data["Times"] = []
        cmd_data["RepeatIntervalMinutes"] = []
        cmd_data["Type"] = []
        cmd_data["Mode"] = []
        cmd_data["Day"] = []

    # 🧹 Clear editor UI
    for widget in rows_frame.winfo_children():
        widget.destroy()
    row_widgets.clear()
    on_frame_configure(None)

    # ❌ Deselect last selected command
    current_command_key = None
    add_btn.config(state="disabled")
    default_btn.config(state="disabled")
    previous_selected_command = None

    # ако користиш Listbox за AutoCommands
    try:
        command_listbox.selection_clear(0, "end")
        command_listbox.activate(-1)
    except:
        pass

    # 🔥 AUTO SAVE
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2, separators=(',', ': '))

    config_dirty = False
    save_btn.config(state="disabled")

    show_status_message(
        "⚠️ ALL AutoCommands RESET & auto-saved",
        "danger",
        3000
    )
    
    # По 3000ms прикажи трајна бела порака за селекција
    def show_select_command_status():
        show_status_message(
            "⚠️ Select a COMMAND first, then edit selected COMMAND!",
            style="warning",  # бела / неутрална боја
            duration=None   # останува на екранот
        )
    root.after(3000, show_select_command_status)

# --- Confirm Save Only If Dirty ---
def confirm_save_command_if_dirty():
    global config_dirty, current_command_key

    if not config_dirty:
        return True  # нема промени → може да продолжи

    answer = messagebox.askyesno(
        "Unsaved Changes",
        "You have unsaved changes for this command.\nDo you want to save them?"
    )

    if answer:
        # YES → Save current command
        if current_command_key is not None:
            save_config()  # GUI → config → JSON
    else:
        # NO → ресетирај dirty бидејќи одлучивме да не зачувуваме
        config_dirty = False
        save_btn.config(state="disabled")

    # NO или YES → дозволи промена на selection
    return True

# --- Select Command ---
def select_command(event):
    global current_command_key, row_widgets, previous_selected_index

    clicked_index = command_listbox.nearest(event.y)
    bbox = command_listbox.bbox(clicked_index)
    if not bbox:
        return
    x1, y1, width, height = bbox
    if event.y < y1 or event.y > y1 + height:
        return

    # 🔥 If same command → do nothing
    if current_command_key is not None:
        current_index = list(config["AutoCommands"].keys()).index(current_command_key)
        if clicked_index == current_index:
            return

    # 🔥 Ask to save only if dirty
    if not confirm_save_command_if_dirty():
        return  # Cancel pressed → stay on current

    # --- Restore previous color ---
    if previous_selected_index is not None and previous_selected_index != clicked_index:
        original_key = list(config["AutoCommands"].keys())[previous_selected_index]
        display_name = original_key.lstrip("/")
        command_listbox.delete(previous_selected_index)
        command_listbox.insert(previous_selected_index, f"{previous_selected_index+1}. {display_name}")
        r, g, b = [random.randint(100,255) for _ in range(3)]
        command_listbox.itemconfig(previous_selected_index, foreground=f"#{r:02X}{g:02X}{b:02X}")

    # --- Select new command ---
    command_listbox.selection_clear(0, "end")
    command_listbox.selection_set(clicked_index)
    current_command_key = list(config["AutoCommands"].keys())[clicked_index]
    display_name = current_command_key.lstrip("/")
    command_listbox.activate(clicked_index)
    command_listbox.see(clicked_index)
    previous_selected_index = clicked_index

    # --- Clear rows ---
    for widget in rows_frame.winfo_children():
        widget.destroy()
    row_widgets.clear()

    # --- Load rows ---
    cmd_data = config["AutoCommands"][current_command_key]
    for idx in range(len(cmd_data["Times"])):
        add_row(cmd_data, idx)
    on_frame_configure(None)      

    default_btn.config(state="normal")
    add_btn.config(state="normal")   # 👈 enable Add Row

    # --- Update description ---
    description = cmd_data.get("Description", "No description available.")
    for w in command_desc_label.winfo_children():
        w.destroy()

    text_widget = tk.Text(
        command_desc_label,
        width=50,
        height=5,
        bg="#2D2D30",
        bd=0,
        highlightthickness=0,
        wrap="word"
    )
    text_widget.pack(expand=True, fill="both")
    text_widget.tag_configure("selected", foreground="#FFFFFF", font=("Segoe UI", 13, "bold"), justify="center")
    text_widget.tag_configure("description", foreground="#FFD700", font=("Segoe UI", 12, "italic"), justify="center")
    text_widget.insert("end", f"Selected: {display_name}\n", "selected")
    text_widget.insert("end", description, "description")
    text_widget.configure(state="disabled")

    # 🔥 Reset dirty after loading new command
    config_dirty = False
    save_btn.config(state="disabled")
    update_status_no_command()

# --- Add / Delete Row Functions ---
def add_row(cmd_data=None, idx=None):
    if len(row_widgets) >= MAX_ROWS:
        messagebox.showwarning("Max Rows", f"You cannot add more than {MAX_ROWS} rows.")
        return

    row_index = len(row_widgets)
    spin_font = ("Segoe UI", 14, "bold")
    spin_bg = "#1E1E1E"
    spin_fg = "#FFFFFF"

    frame = tk.Frame(rows_frame, bg="#1E1E1E")
    frame.grid(row=row_index, column=0, sticky="w", pady=6)

    # Row number
    num_label = tk.Label(frame, text=f"{row_index+1}.", width=4, bg="#1E1E1E", fg="#FFD700", font=spin_font)
    num_label.pack(side="left", padx=5)

    # --- Time HH:MM:SS ---
    if cmd_data:
        h, m, s = map(int, cmd_data["Times"][idx].split(":"))
    else:
        h, m, s = 0, 0, 0
    h_var = tk.StringVar(value=f"{h:02d}")
    m_var = tk.StringVar(value=f"{m:02d}")
    s_var = tk.StringVar(value=f"{s:02d}")
    time_frame = tk.Frame(frame, bg="#1E1E1E")
    time_frame.pack(side="left", padx=(0,20))
    tk.Spinbox(time_frame, from_=0, to=23, width=3, textvariable=h_var, font=spin_font,
               state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center").pack(side="left")
    tk.Label(time_frame, text=":", bg="#1E1E1E", fg=spin_fg, font=spin_font).pack(side="left")
    tk.Spinbox(time_frame, from_=0, to=59, width=3, textvariable=m_var, font=spin_font,
               state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center").pack(side="left")
    tk.Label(time_frame, text=":", bg="#1E1E1E", fg=spin_fg, font=spin_font).pack(side="left")
    tk.Spinbox(time_frame, from_=0, to=59, width=3, textvariable=s_var, font=spin_font,
               state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center").pack(side="left")

    # --- Repeat ---
    r_var = tk.StringVar(value=str(cmd_data["RepeatIntervalMinutes"][idx]) if cmd_data else "0")
    r_spin = tk.Spinbox(frame, from_=0, to=10000, width=6, textvariable=r_var, font=spin_font,
                        state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center")
    r_spin.pack(side="left", padx=(20,50))

    # --- Type ---
    if cmd_data and "Type" in cmd_data:
        type_value = cmd_data["Type"][idx] if isinstance(cmd_data["Type"], list) else cmd_data["Type"]
    else:
        type_value = "daily"
    type_var = tk.StringVar(value=type_value)
    type_combo = ttk.Combobox(
        frame,
        textvariable=type_var,
        values=["daily", "weekly", "monthly", "yearly"],
        state="readonly",
        width=10,
        bootstyle="info"
    )
    type_combo.pack(side="left", padx=(10,20))
    
    # --- Tooltip for Type combobox ---
    tooltip = Tooltip(type_combo)

    def update_tooltip(*args):
        val = type_var.get()
        if val == "daily":
            tooltip.set_text("Daily → executes every day (FIKS Works only when this is SELECT!)")
        elif val == "weekly":
            tooltip.set_text("Weekly → executes on Sunday. (Default is LOOP!)")
        elif val == "monthly":
            tooltip.set_text("Monthly → executes on the last day of the month. (Default is LOOP!)")
        elif val == "yearly":
            tooltip.set_text("Yearly → executes on the last day of the year. (Default is LOOP!)")
        else:
            tooltip.set_text("")

    type_var.trace_add("write", update_tooltip)
    update_tooltip()  # initialize tooltip

    # --- Date Spinners ---
    today = date.today()
    if cmd_data and "Day" in cmd_data:
        try:
            y, mo, d = map(int, cmd_data["Day"][idx].split("-"))
        except:
            y, mo, d = today.year, today.month, today.day
    else:
        y, mo, d = today.year, today.month, today.day

    year_var = tk.StringVar(value=str(y))
    month_var = tk.StringVar(value=f"{mo:02d}")
    day_var = tk.StringVar(value=f"{d:02d}")

    date_frame = tk.Frame(frame, bg="#1E1E1E")
    date_frame.pack(side="left", padx=(0,10))

    year_spin = tk.Spinbox(date_frame, from_=today.year, to=today.year+10, width=5, textvariable=year_var,
                            state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center", font=spin_font)
    year_spin.pack(side="left")
    tk.Label(date_frame, text="-", bg="#1E1E1E", fg=spin_fg, font=spin_font).pack(side="left")
    month_spin = tk.Spinbox(date_frame, from_=1, to=12, width=3, textvariable=month_var,
                            state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center", font=spin_font)
    month_spin.pack(side="left")
    tk.Label(date_frame, text="-", bg="#1E1E1E", fg=spin_fg, font=spin_font).pack(side="left")
    day_spin = tk.Spinbox(date_frame, from_=1, to=31, width=3, textvariable=day_var,
                          state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center", font=spin_font)
    day_spin.pack(side="left")

    # --- Update day limits ---
    def update_day_limit(*args):
        try:
            year = int(year_var.get())
            month = int(month_var.get())
        except ValueError:
            return
        max_day = calendar.monthrange(year, month)[1]
        day_spin.config(to=max_day)
        try:
            current_day = int(day_var.get())
        except ValueError:
            current_day = 1
        if current_day > max_day:
            day_var.set(f"{max_day:02d}")
        # Limit past dates
        if year == today.year and month == today.month and int(day_var.get()) < today.day:
            day_var.set(f"{today.day:02d}")
        if year < today.year:
            year_var.set(str(today.year))
        elif year == today.year and month < today.month:
            month_var.set(f"{today.month:02d}")

    year_var.trace_add("write", update_day_limit)
    month_var.trace_add("write", update_day_limit)
    day_var.trace_add("write", update_day_limit)

    # --- Mode Button ---
    mode_val = cmd_data["Mode"][idx] if cmd_data and "Mode" in cmd_data else "loop"
    mode_var = tk.StringVar(value=mode_val)

    def toggle_mode_visual(*args):
        cmd_type = type_var.get()
        if cmd_type != "daily":
            # If not daily, force loop and disable spinner
            mode_var.set("loop")
            mode_btn.config(text="Loop", bg="#FFD700", fg="#000000", state="disabled")
            year_spin.config(state="disabled")
            month_spin.config(state="disabled")
            day_spin.config(state="disabled")
        else:
            # If daily, allow loop/fixed
            mode_btn.config(state="normal")
            if mode_var.get() == "loop":
                mode_btn.config(text="Loop", bg="#FFD700", fg="#000000")
                year_spin.config(state="disabled")
                month_spin.config(state="disabled")
                day_spin.config(state="disabled")
            else:
                mode_btn.config(text="Fiks", bg="#32CD32", fg="#000000")
                year_spin.config(state="readonly")
                month_spin.config(state="readonly")
                day_spin.config(state="readonly")

    mode_var.trace_add("write", toggle_mode_visual)
    # Also trace type_var changes to re-run toggle whenever type changes
    type_var.trace_add("write", toggle_mode_visual)

    mode_btn = tk.Button(
        frame,
        text="Loop",
        font=("Segoe UI", 11, "bold"),
        width=8,
        height=1,
        relief="raised",
        bd=2,
        command=lambda: mode_var.set("fixed" if mode_var.get() == "loop" else "loop")
    )
    mode_btn.pack(side="left", padx=(10,10))
    toggle_mode_visual()

    # --- Delete Button ---
    del_btn = ttk.Button(frame, text="Delete", bootstyle="danger", command=lambda f=frame: delete_row(f))
    del_btn.pack(side="left", padx=(10,88))

    # --- Trace changes ---
    h_var.trace_add("write", mark_dirty)
    m_var.trace_add("write", mark_dirty)
    s_var.trace_add("write", mark_dirty)
    r_var.trace_add("write", mark_dirty)
    type_var.trace_add("write", mark_dirty)
    year_var.trace_add("write", mark_dirty)
    month_var.trace_add("write", mark_dirty)
    day_var.trace_add("write", mark_dirty)
    mode_var.trace_add("write", mark_dirty)

    # Save row
    row_widgets.append((frame, (h_var, m_var, s_var), r_var, type_var, (year_var, month_var, day_var), mode_var))

# --- Delete Row ---
def delete_row(frame):
    global row_widgets, config_dirty  # <- make config_dirty global
    idx_to_delete = None
    for i, row in enumerate(row_widgets):
        if row[0] == frame:
            idx_to_delete = i
            break
    if idx_to_delete is not None:
        row_widgets[idx_to_delete][0].destroy()
        row_widgets.pop(idx_to_delete)
        # Reindex
        for i, row in enumerate(row_widgets):
            row_frame = row[0]
            row_frame.grid_configure(row=i)
            row_frame.children[list(row_frame.children.keys())[0]].config(text=f"{i+1}")
        config_dirty = True  # <- now properly sets the global
        save_btn.config(state="normal")  
        on_frame_configure(None)   

# --- Load Config ---
config = load_config()
current_script_index = None
row_widgets = []

# --- Main Window ---
style = Style(theme="darkly")
root = style.master
root.title("Automation Commands Editor")
root.geometry("1355x588")
root.configure(bg="#1E1E1E")
root.iconbitmap(str(ICON_PATH))

# --- Left Frame: Script List ---
left_frame = tk.Frame(root, bg="#2D2D30")
left_frame.pack(side="left", fill="y", padx=10, pady=10)

# Функција која менува боја на Label-от
def animate_label_color():
    r = random.randint(50, 255)
    g = random.randint(50, 255)
    b = random.randint(50, 255)
    color_hex = f"#{r:02X}{g:02X}{b:02X}"
    info_label.config(fg=color_hex)
    left_frame.after(3000, animate_label_color)  # повторува секој 3 секунди

# --- Долна линија текст, секогаш видлива ---
info_label = tk.Label(
    left_frame,
    text="𝘼𝙪𝙩𝙤𝙋𝙞𝙡𝙤𝙩 𝙎𝙮𝙨𝙩𝙚𝙢",
    bg="#2D2D30",
    fg="#FFD700",
    font=("Segoe UI", 18, "bold"),  # поголем и живописен фонт
    wraplength=350,
    justify="center"
)
info_label.pack(side="bottom", pady=(15,10))  # секогаш на дното

# Почни ја анимацијата на бојата
animate_label_color()

# --- Command Description (shown when command is selected) ---
command_desc_label = tk.Label(
    left_frame,
    text="",
    bg="#2D2D30",
    font=("Arial", 14,),  
    wraplength=330,
    justify="center",
)
command_desc_label.pack(side="bottom", pady=(5, 5))

# --- Лого пред Scripts ---
logo_path = str(ICON_PATH) 
logo_image = Image.open(logo_path)
logo_image = logo_image.resize((50, 50), Image.Resampling.LANCZOS)  # постави ширина/висина
logo_photo = ImageTk.PhotoImage(logo_image)

logo_label = tk.Label(left_frame, image=logo_photo, bg="#2D2D30")
logo_label.image = logo_photo  # must keep reference
logo_label.pack(pady=(10,5))  # растојание од врвот

tk.Label(left_frame, text="Commands List:", bg="#2D2D30", fg="#FFD700", font=("Segoe UI", 19, "bold")).pack(pady=10)

# Listbox
listbox_font = tkFont.Font(family="Segoe UI", size=13, weight="bold")
command_listbox = tk.Listbox(
    left_frame,
    bg="#3C3F41",
    font=listbox_font,
    width=35,
    height=35,
    selectbackground="#FFD700",
    selectforeground="#000000",
    activestyle="none"
)
command_listbox.pack(fill="y", expand=True, pady=10)

for i, key in enumerate(config["AutoCommands"].keys()):
    display_text = key.lstrip("/")
    command_listbox.insert("end", f"{i+1}. {display_text}")

    r, g, b = [random.randint(100, 255) for _ in range(3)]
    color_hex = f"#{r:02X}{g:02X}{b:02X}"
    command_listbox.itemconfig("end", foreground=color_hex)

    # Random color for text
    r, g, b = [random.randint(100, 255) for _ in range(3)]
    color_hex = f"#{r:02X}{g:02X}{b:02X}"
    command_listbox.itemconfig("end", foreground=color_hex)

# Bind selection
command_listbox.bind("<Button-1>", select_command)

# --- Right Frame: Headers + Rows + Buttons ---
right_frame = tk.Frame(root, bg="#1E1E1E")
right_frame.pack(side="right", fill="both", expand=True, padx=10, pady=10)

# --- Wrapper за canvas + scrollbar ---
canvas_frame = tk.Frame(right_frame, bg="#1E1E1E")
canvas_frame.pack(fill="both", expand=True)

canvas = tk.Canvas(canvas_frame, bg="#1E1E1E", highlightthickness=0)
canvas.pack(side="left", fill="both", expand=True)

v_scroll = tk.Scrollbar(canvas_frame, orient="vertical", command=canvas.yview)
v_scroll.pack(side="right", fill="y")

canvas.configure(yscrollcommand=v_scroll.set)

scrollable_frame = tk.Frame(canvas, bg="#1E1E1E")
canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
canvas.update_idletasks()

# Headers
headers_frame = tk.Frame(scrollable_frame, bg="#1E1E1E")
headers_frame.pack(fill="x", pady=(0,5))
header_font = ("Segoe UI", 14, "bold")
tk.Label(headers_frame, text="#", width=4, bg="#1E1E1E", fg="#FFD700", font=header_font).pack(side="left", padx=0)
tk.Label(headers_frame, text="Time (HH:MM:SS)", width=20, bg="#1E1E1E", fg="#00FF00", font=header_font).pack(side="left", padx=(0,0))
tk.Label(headers_frame, text="Repeat Min", width=10, bg="#1E1E1E", fg="#1E90FF", font=header_font).pack(side="left", padx=(0,0))
tk.Label(headers_frame, text="Type", width=10, bg="#1E1E1E", fg="#1E90FF", font=header_font).pack(side="left", padx=(0,0))
tk.Label(headers_frame, text="Date (YY:MM:DD)", width=20, bg="#1E1E1E", fg="#1E90FF", font=header_font).pack(side="left", padx=(0,0))
tk.Label(headers_frame, text="Interval", width=10, bg="#1E1E1E", fg="#1E90FF", font=header_font).pack(side="left", padx=(0,0))
tk.Label(headers_frame, text="Delete", width=8, bg="#1E1E1E", fg="#FF4500", font=header_font).pack(side="left", padx=(0,0))

# Rows frame
rows_frame = tk.Frame(scrollable_frame, bg="#1E1E1E")
rows_frame.pack(fill="both", expand=True, pady=10)

# --- Configure canvas scrollregion ---
def on_frame_configure(event=None):
    canvas.update_idletasks()  # update sizes
    
    content_height = scrollable_frame.winfo_reqheight()
    canvas_height = canvas.winfo_height()
    
    # If no rows or content fits → hide scrollbar
    if len(row_widgets) == 0 or content_height <= canvas_height:
        if v_scroll.winfo_ismapped():
            v_scroll.pack_forget()
        canvas.configure(scrollregion=(0,0,canvas.winfo_width(), canvas_height))
        canvas.yview_moveto(0)
    else:
        if not v_scroll.winfo_ismapped():
            v_scroll.pack(side="right", fill="y")
        canvas.configure(scrollregion=(0,0,canvas.winfo_width(), content_height))

scrollable_frame.bind("<Configure>", on_frame_configure)

# --- Mousewheel scroll ---
def _on_mousewheel(event):
    content_height = scrollable_frame.winfo_reqheight()
    canvas_height = canvas.winfo_height()

    if content_height > canvas_height:
        canvas.yview_scroll(int(-1 * (event.delta // 120)), "units")

canvas.bind("<Enter>", lambda e: canvas.focus_set())
canvas.bind_all("<MouseWheel>", _on_mousewheel)

# Buttons frame
buttons_frame = tk.Frame(right_frame, bg="#1E1E1E")
buttons_frame.pack(pady=15, fill="x")
buttons_row = tk.Frame(buttons_frame, bg="#1E1E1E")
buttons_row.pack(anchor="center")

# --- Status Label ---
status_label = ttk.Label(buttons_frame, text="", bootstyle="info", justify="center")
status_label.pack_forget()  # стартно не се гледа

# --- Status Message ---
def show_status_message(message, style="info", duration=2000):
    status_label.config(text=message, bootstyle=style)
    status_label.pack(before=buttons_row, pady=(0,5))
    if duration is not None:
        status_label.after(duration, status_label.pack_forget)

# --- Add Row with status ---
def add_row_with_status():
    global config_dirty
    add_row()
    config_dirty = True
    save_btn.config(state="normal")
    show_status_message("✔ Row added", "info", 1500)

# --- Save Config with status ---
def save_config_with_status():
    if current_command_key is not None:
        save_config()
        show_status_message("✔ Command configuration saved", "success", 3000)
    else:
        save_all_config()

# --- Update buttons & status based on command selection ---
def update_status_no_command():
    if current_command_key is None:
        # нема селекција → покажи порака и исклучи копчиња
        show_status_message("⚠️ Select a COMMAND first, then edit selected COMMAND!", "warning", duration=None)
        add_btn.config(state="disabled")
        save_btn.config(state="disabled")
        default_btn.config(state="disabled")
    else:
        # има селекција → сокриј порака и вклучи копчиња
        status_label.pack_forget()
        add_btn.config(state="normal")
        save_btn.config(state="normal")
        default_btn.config(state="normal")


# --- Buttons ---
add_btn = ttk.Button(buttons_row, text="Add Row", bootstyle="info", command=add_row_with_status, state="disabled")
add_btn.pack(side="left", padx=20)

save_btn = ttk.Button(buttons_row, text="Save Config", bootstyle="success", command=save_config_with_status, state="disabled")
save_btn.pack(side="left", padx=20)

default_btn = ttk.Button(buttons_row, text="Default", bootstyle="warning", command=reset_to_default, state="disabled")
default_btn.pack(side="left", padx=20)

list_btn = ttk.Button(buttons_row, text="List All", bootstyle="info", command=open_autocommands_table)
list_btn.pack(side="left", padx=20)

reset_all_btn = ttk.Button(buttons_row, text="Reset All", bootstyle="danger", command=reset_all_autocommands)
reset_all_btn.pack(side="left", padx=20)

update_status_no_command()

# --- Долна линија текст, секогаш видлива ---
buttons_info_label = ttk.Label(
    buttons_frame,
    text="You can add up to 35 rows. Save Config and Default USE for every COMMAND separately. FIKS USE only when Type Selection is *daily*.",
    bootstyle="secondary",
    justify="center",
    font=("Segoe UI", 11)
)
buttons_info_label.pack(side="bottom", pady=(15,0))  # најдолу

# --- Save on Close ---
def on_close():
    global config_dirty

    if config_dirty:
        answer = messagebox.askyesnocancel(
            "Unsaved Changes",
            "You have unsaved changes.\nDo you want to save before exiting?"
        )

        if answer is None:
            return  # Cancel close

        if answer:
            # Ако има активна команда → зачувај ја во config
            if current_command_key is not None:
                save_config()

            # СЕКОГАШ зачувај го целиот config во JSON
            save_all_config()

    root.destroy()

root.protocol("WM_DELETE_WINDOW", on_close)
root.mainloop()

################################################################################################################### End CommandEditor.


############  PIP Install  ##############
# pip install ttkbootstrap pillow


############ .EXE COMPYLER  Install  ##############
# pip install pyinstaller ttkbootstrap pillow ZA.EXE FILE COMPILER

# python -m pip install --upgrade pip setuptools wheel  ZA.EXE FILE COMPILER

# python -m pip install pyinstaller  ZA.EXE FILE COMPILER

# pyinstaller --noconsole --onefile --windowed --add-data "media;media" --add-data "JSON;JSON" CommandsEditor.py  - CommandsEditor.exe

# pyinstaller --noconsole --onefile --windowed --add-data "media;media" --add-data "JSON;JSON" ScriptsEditor.py  - ScriptsEditor.exe

# pyinstaller --noconsole --onefile Camera.py  - Camera.exe




