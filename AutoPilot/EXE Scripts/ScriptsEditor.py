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
CONFIG_FILE = APP_ROOT / "JSON" / "scripts_edit.json"
DEFAULT_CONFIG_FILE = APP_ROOT / "JSON" / "scripts_default.json"
ICON_PATH = APP_ROOT / "media" / "scripts.ico"
MAX_ROWS = 35

# --- Global state ---
previous_selected_index = None
current_command_key = None
row_widgets = []

# --- Helper Functions ---
def load_config():
    with open(CONFIG_FILE, "r") as f:
        return json.load(f)
        
# --- Save Config ---          
def save_config():
    global current_script_index

    script = config["ScheduledScripts"][current_script_index]

    # Инициализирај ги листите
    script["Commands"] = []
    script["Times"] = []
    script["DelaySeconds"] = []
    script["RepeatIntervalMinutes"] = []
    script["Mode"] = []
    script["Day"] = []  # Day е последно

    for widgets in row_widgets:
        _, cmd_var, t_vars, d_var, r_var, date_vars, mode_var = widgets
        h, m, s = [v.get() for v in t_vars]
        time_str = f"{int(h):02d}:{int(m):02d}:{int(s):02d}"
        y_var, m_var, d_var_spin = date_vars

        # Command, Time, Delay, Repeat, Mode
        script["Commands"].append(cmd_var.get())
        script["Times"].append(time_str)
        script["DelaySeconds"].append(int(d_var.get()))
        script["RepeatIntervalMinutes"].append(int(r_var.get()))
        script["Mode"].append(mode_var.get())

        # Day → празно ако е loop, точен датум ако е fixed
        if mode_var.get() == "fixed":
            y, mo, d = int(y_var.get()), int(m_var.get()), int(d_var_spin.get())
            script["Day"].append(f"{y:04d}-{mo:02d}-{d:02d}")
        else:
            script["Day"].append("")  # Loop → празен стринг

    # Зачувај JSON
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2, separators=(',', ': '))

    messagebox.showinfo("Saved", f"Config saved for {script['Path']}")
    global config_dirty
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
def open_json_table():
    table_win = tk.Toplevel(root)
    table_win.title("Scripts Overview (Read Only)")
    table_win.geometry("1500x800")
    table_win.configure(bg="#1E1E1E")

    columns = ["Script", "Row", "Command", "Time", "Delay", "Repeat", "Mode", "Day"]

    tree = ttk.Treeview(table_win, columns=columns, show="headings")
    tree.pack(fill="both", expand=True, padx=10, pady=10)

    # --- Apply style AFTER widget is mapped ---
    style = ttk.Style(table_win)
    def apply_tree_style():
        style.configure(
            "Treeview",
            font=("Segoe UI", 16),
            rowheight=45,
            background="#1E1E1E",
            fieldbackground="#1E1E1E",
            foreground="#FFFFFF"
        )
        style.configure(
            "Treeview.Heading",
            font=("Segoe UI", 18, "bold"),
            foreground="#FFD700",
            background="#1E1E1E"
        )
    table_win.after_idle(apply_tree_style)

    # --- Columns ---
    for col in columns:
        tree.heading(col, text=col)
        tree.column(col, anchor="center", width=150)

    from datetime import datetime

    # Боја за секоја скрипта (loop)
    script_colors = [
        f"#{random.randint(60,200):02X}{random.randint(60,200):02X}{random.randint(60,200):02X}"
        for _ in range(len(config["ScheduledScripts"]))
    ]

    for script_index, script in enumerate(config["ScheduledScripts"]):
        script_name = os.path.basename(script["Path"])
        base_color = script_colors[script_index]

        commands = script.get("Commands", [])
        if not commands:
            # Ако нема команди, внеси ред No Data
            tree.insert(
                "",
                "end",
                values=(script_name, "-", "No Data", "-", "-", "-", "-", "-"),
                tags=(f"no_data_{script_index}",)
            )
            tree.tag_configure(f"no_data_{script_index}", background="#2D2D30", foreground="#CFCFCF")
        else:
            for i in range(len(commands)):
                day_val = script.get("Day", [""])[i] if script.get("Day") else ""
                time_val = script["Times"][i] if "Times" in script else "-"
                delay_val = script["DelaySeconds"][i] if "DelaySeconds" in script else "-"
                repeat_val = script["RepeatIntervalMinutes"][i] if "RepeatIntervalMinutes" in script else "-"
                mode_val = script.get("Mode", ["loop"])[i] if script.get("Mode") else "loop"

                # --- Past check ---
                is_past = False
                if day_val:
                    try:
                        day_obj = datetime.strptime(day_val, "%Y-%m-%d").date()
                        time_parts = list(map(int, time_val.split(":")))
                        dt_obj = datetime(day_obj.year, day_obj.month, day_obj.day, *time_parts)
                        if dt_obj < datetime.now():
                            is_past = True
                    except:
                        pass

                # --- Colors ---
                if is_past:
                    bg_color, fg_color = "#8B0000", "#FFFFFF"
                elif mode_val == "fixed":
                    bg_color, fg_color = "#2E8B57", "#FFFFFF"
                else:
                    bg_color, fg_color = "#2D2D30", "#CFCFCF"

                tag_name = f"script_{script_index}_{i}"
                tree.tag_configure(tag_name, background=bg_color, foreground=fg_color)

                tree.insert(
                    "",
                    "end",
                    values=(
                        script_name,
                        i+1,
                        commands[i],
                        time_val,
                        delay_val,
                        repeat_val,
                        mode_val,
                        day_val if day_val else "-"
                    ),
                    tags=(tag_name,)
                )

        # spacer помеѓу скриптите
        if script_index != len(config["ScheduledScripts"]) - 1:
            spacer_tag = f"spacer_{script_index}"
            tree.insert("", "end", values=("", "", "", "", "", "", "", ""), tags=(spacer_tag,))
            tree.tag_configure(spacer_tag, background="#1E1E1E")
            
# --- Reset Default ---
def reset_to_default():
    global config, row_widgets, config_dirty

    if current_script_index is None:
        return

    answer = messagebox.askyesno(
        "Reset to Default",
        "Are you sure?\nOnly the selected script will be reset."
    )
    if not answer:
        return

    if not os.path.exists(DEFAULT_CONFIG_FILE):
        messagebox.showerror(
            "Missing default file",
            f"script_default.json not found!\nPath:\n{DEFAULT_CONFIG_FILE}"
        )
        return

    with open(DEFAULT_CONFIG_FILE, "r") as f:
        default_config = json.load(f)

    # 🔁 Reset само активниот script
    config["ScheduledScripts"][current_script_index] = \
        default_config["ScheduledScripts"][current_script_index]

    script = config["ScheduledScripts"][current_script_index]

    # --- За секој ред, Mode = loop и Day = "" ---
    if "Mode" not in script:
        script["Mode"] = []

    for i in range(len(script["Commands"])):
        if i >= len(script["Mode"]):
            script["Mode"].append("loop")
        else:
            script["Mode"][i] = "loop"

        if i >= len(script.get("Day", [])):
            if "Day" not in script:
                script["Day"] = []
            script["Day"].append("")
        else:
            script["Day"][i] = ""

    # --- Refresh UI ---
    for widget in rows_frame.winfo_children():
        widget.destroy()
    row_widgets.clear()
    on_frame_configure()

    for idx in range(len(script["Commands"])):
        add_row(script, idx)

    # 🔥 AUTO SAVE 
    save_config()        # ← автоматски снима
    save_all_config()    # ← сигурно во JSON

    config_dirty = False
    save_btn.config(state="disabled")

    show_status_message(
        "↺ Script reset to default & auto-saved",
        "success",
        3000
    )
    
# --- Mark Dirty ---  
def mark_dirty(*args):
    global config_dirty
    config_dirty = True
    save_btn.config(state="normal")
    
# --- Reset JSON File ---   
def reset_all_scripts():
    global config, row_widgets, config_dirty, current_script_index

    answer = messagebox.askyesno(
        "RESET ALL SCRIPTS",
        "⚠️ WARNING!\n\n"
        "This will ERASE ALL rows for ALL scripts.\n\n"
        "Commands, Times, Delay, Repeat, Mode and Day\n"
        "will be completely cleared.\n\n"
        "Do you want to continue?"
    )

    if not answer:
        return

    # --- Clear ALL ScheduledScripts ---
    for script in config["ScheduledScripts"]:
        script["Commands"] = []
        script["Times"] = []
        script["DelaySeconds"] = []
        script["RepeatIntervalMinutes"] = []
        script["Mode"] = []
        script["Day"] = []

    # --- Clear editor UI ---
    for widget in rows_frame.winfo_children():
        widget.destroy()
    row_widgets.clear()
    on_frame_configure()

    # ❌ Deselect last selected script
    current_script_index = None
    add_btn.config(state="disabled")
    default_btn.config(state="disabled")

    # Clear Listbox selection
    try:
        script_listbox.selection_clear(0, "end")
        script_listbox.activate(-1)
    except:
        pass

    # 🔥 AUTO SAVE
    with open(CONFIG_FILE, "w") as f:
        json.dump(config, f, indent=2, separators=(',', ': '))

    config_dirty = False
    save_btn.config(state="disabled")

    # --- Temporary toast ---
    show_status_message(
        "⚠️ ALL scripts RESET & auto-saved",
        "danger",
        3000
    )

    # --- After 3000ms show permanent warning ---
    def show_select_script_status():
        show_status_message(
            "⚠️ Select a SCRIPT first, then edit selected SCRIPT!",
            style="warning",  # neutral permanent warning
            duration=None    # stays on screen
        )

    root.after(3000, show_select_script_status)

# --- Confirm Save Only If Dirty (само за Scripts) ---
def confirm_save_if_dirty():
    global config_dirty, current_script_index

    if not config_dirty:
        return True  # нема промени → може да продолжи

    answer = messagebox.askyesno(
        "Unsaved Changes",
        "You have unsaved changes.\nDo you want to save them?"
    )

    if answer:
        # YES → save
        if current_script_index is not None:
            save_config()      # зачува тековен config
            save_all_config()  # ако имаш и целосно save за scripts
    else:
        # NO → игнорирај save, но ресетирај dirty
        config_dirty = False
        save_btn.config(state="disabled")

    # YES или NO → дозволи да продолжи
    return True

# --- Select Script ---
def select_script(event):
    global current_script_index, row_widgets, previous_selected_index

    clicked_index = script_listbox.nearest(event.y)
    bbox = script_listbox.bbox(clicked_index)
    if not bbox:
        return
    x1, y1, width, height = bbox
    if event.y < y1 or event.y > y1 + height:
        return

    # 🔥 Ако е ист script → ништо
    if clicked_index == current_script_index:
        return

    # 🔥 Поп-up за Save ако е dirty
    if not confirm_save_if_dirty():
        # CANCEL → остани на старата селекција, не менувај highlight
        if previous_selected_index is not None:
            script_listbox.selection_clear(0, "end")
            script_listbox.selection_set(previous_selected_index)
            script_listbox.activate(previous_selected_index)
            script_listbox.see(previous_selected_index)
        return

    # --- Restore previous color (YES или NO) ---
    if previous_selected_index is not None:
        original_path = config["ScheduledScripts"][previous_selected_index]["Path"]
        original_name = os.path.basename(original_path)

        script_listbox.delete(previous_selected_index)
        script_listbox.insert(previous_selected_index, f"{previous_selected_index+1}. {original_name}")

        r, g, b = [random.randint(100, 255) for _ in range(3)]
        script_listbox.itemconfig(
            previous_selected_index,
            foreground=f"#{r:02X}{g:02X}{b:02X}"
        )

    # --- Select new script ---
    script_listbox.selection_clear(0, "end")
    script_listbox.selection_set(clicked_index)
    current_script_index = clicked_index
    previous_selected_index = clicked_index
    script_listbox.activate(clicked_index)
    script_listbox.see(clicked_index)

    # --- Clear rows & load new script ---
    for widget in rows_frame.winfo_children():
        widget.destroy()
    row_widgets.clear()

    script_data = config["ScheduledScripts"][current_script_index]
    for idx in range(len(script_data["Commands"])):
        add_row(script_data, idx)
    on_frame_configure()     

    default_btn.config(state="normal")
    add_btn.config(state="normal")   # 👈 enable Add Row

    # --- Update description ---
    description = script_data.get("Description", "No description available.")
    script_name = os.path.basename(script_data["Path"])

    for w in script_desc_label.winfo_children():
        w.destroy()

    text_widget = tk.Text(
        script_desc_label,
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
    text_widget.insert("end", f"Selected: {script_name}\n", "selected")
    text_widget.insert("end", description, "description")
    text_widget.configure(state="disabled")

    # 🔥 Reset dirty after loading new script
    config_dirty = False
    save_btn.config(state="disabled")
    update_status_no_selection()

# --- Add / Delete Row Functions ---
def add_row(script=None, idx=None):
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

    # Command
    cmd_var = tk.StringVar(value=script["Commands"][idx] if script else "1")
    cmd_spin = tk.Spinbox(frame, from_=0, to=100, textvariable=cmd_var, width=6, font=spin_font,
                          state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center")
    cmd_spin.pack(side="left", padx=(5, 50))

    # Time HH:MM:SS
    if script:
        h, m, s = map(int, script["Times"][idx].split(":"))
    else:
        h, m, s = 0, 0, 0
    h_var = tk.StringVar(value=f"{h:02d}")
    m_var = tk.StringVar(value=f"{m:02d}")
    s_var = tk.StringVar(value=f"{s:02d}")
    time_frame = tk.Frame(frame, bg="#1E1E1E")
    time_frame.pack(side="left", padx=(0, 20))
    tk.Spinbox(time_frame, from_=0, to=23, width=3, textvariable=h_var, font=spin_font,
               state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center").pack(side="left")
    tk.Label(time_frame, text=":", bg="#1E1E1E", fg=spin_fg, font=spin_font).pack(side="left")
    tk.Spinbox(time_frame, from_=0, to=59, width=3, textvariable=m_var, font=spin_font,
               state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center").pack(side="left")
    tk.Label(time_frame, text=":", bg="#1E1E1E", fg=spin_fg, font=spin_font).pack(side="left")
    tk.Spinbox(time_frame, from_=0, to=59, width=3, textvariable=s_var, font=spin_font,
               state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center").pack(side="left")

    # Delay
    d_var = tk.StringVar(value=str(script["DelaySeconds"][idx]) if script else "0")
    tk.Spinbox(frame, from_=0, to=1000, width=6, textvariable=d_var, font=spin_font,
               state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center").pack(side="left", padx=(0,35))

    # Repeat
    r_var = tk.StringVar(value=str(script["RepeatIntervalMinutes"][idx]) if script else "0")
    tk.Spinbox(frame, from_=0, to=10000, width=6, textvariable=r_var, font=spin_font,
               state="readonly", readonlybackground=spin_bg, fg=spin_fg, justify="center").pack(side="left", padx=(0,50))

    # --- Date Spinners ---
    today = date.today()
    if script:
        try:
            y, mo, d = map(int, script["Day"][idx].split("-"))
        except:
            y, mo, d = today.year, today.month, today.day
    else:
        y, mo, d = today.year, today.month, today.day

    year_var = tk.StringVar(value=str(y))
    month_var = tk.StringVar(value=f"{mo:02d}")
    day_var = tk.StringVar(value=f"{d:02d}")

    date_frame = tk.Frame(frame, bg="#1E1E1E")
    date_frame.pack(side="left", padx=(0,10))

    # Year/Month/Day spinboxes
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

    def update_day_spinbox(*args):
        try:
            y_val = int(year_var.get())
            m_val = int(month_var.get())
            max_day = calendar.monthrange(y_val, m_val)[1]
            min_day = today.day if (y_val == today.year and m_val == today.month) else 1
            current_day = int(day_var.get())
            if current_day < min_day:
                day_var.set(str(min_day))
            elif current_day > max_day:
                day_var.set(str(max_day))
            day_spin.config(from_=min_day, to=max_day)
        except ValueError:
            pass

    year_var.trace_add("write", update_day_spinbox)
    month_var.trace_add("write", update_day_spinbox)
    update_day_spinbox()

    # --- Mode Toggle (Loop / Fixed) ---
    mode_val = script["Mode"][idx] if script and "Mode" in script else "loop"
    mode_var = tk.StringVar(value=mode_val)

    def toggle_mode_visual(*args):
        if mode_var.get() == "loop":
            mode_btn.config(text="Loop", background="#FFD700", foreground="#000000")
            year_spin.config(state="disabled")
            month_spin.config(state="disabled")
            day_spin.config(state="disabled")
        else:
            mode_btn.config(text="Fiks", background="#32CD32", foreground="#000000")
            year_spin.config(state="readonly")
            month_spin.config(state="readonly")
            day_spin.config(state="readonly")

    mode_var.trace_add("write", toggle_mode_visual)

    # Направи го copy на Delete-style button со боја и padding
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
    mode_btn.pack(side="left", padx=(20,20))
    toggle_mode_visual()  # стартно поставување на бојата и текстот


    # Delete button
    del_btn = ttk.Button(frame, text="Delete", bootstyle="danger", command=lambda f=frame: delete_row(f))
    del_btn.pack(side="left", padx=(20,0))

    # Trace dirty
    cmd_var.trace_add("write", mark_dirty)
    h_var.trace_add("write", mark_dirty)
    m_var.trace_add("write", mark_dirty)
    s_var.trace_add("write", mark_dirty)
    d_var.trace_add("write", mark_dirty)
    r_var.trace_add("write", mark_dirty)
    year_var.trace_add("write", mark_dirty)
    month_var.trace_add("write", mark_dirty)
    day_var.trace_add("write", mark_dirty)
    mode_var.trace_add("write", mark_dirty)

    # Save all vars
    row_widgets.append((frame, cmd_var, (h_var, m_var, s_var), d_var, r_var, (year_var, month_var, day_var), mode_var))

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
        on_frame_configure()        

# --- Load Config ---
config = load_config()
current_script_index = None
row_widgets = []

# --- Main Window ---
style = Style(theme="darkly")
root = style.master
root.title("Automation Scripts Editor")
root.geometry("1570x588")
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
script_desc_label = tk.Label(
    left_frame,
    text="",
    bg="#2D2D30",
    font=("Arial", 14,),  
    wraplength=330,
    justify="center"
)
script_desc_label.pack(side="bottom", pady=(5, 5))

# --- Лого пред Scripts ---
logo_path = str(ICON_PATH) 
logo_image = Image.open(logo_path)
logo_image = logo_image.resize((50, 50), Image.Resampling.LANCZOS)  # постави ширина/висина
logo_photo = ImageTk.PhotoImage(logo_image)

logo_label = tk.Label(left_frame, image=logo_photo, bg="#2D2D30")
logo_label.image = logo_photo  # must keep reference
logo_label.pack(pady=(10,5))  # растојание од врвот

tk.Label(left_frame, text="Scripts List:", bg="#2D2D30", fg="#FFD700", font=("Segoe UI", 19, "bold")).pack(pady=10)

# Фонт за Listbox - bold и поголем height за vertical spacing
listbox_font = tkFont.Font(family="Segoe UI", size=13, weight="bold")

# Listbox со реден број и случајни бои
script_listbox = tk.Listbox(
    left_frame,
    bg="#3C3F41",
    font=listbox_font,
    width=40,
    height=40,
    selectbackground="#FFD700",
    selectforeground="#000000",
    activestyle="none"
)
script_listbox.pack(fill="y", expand=True, pady=10)  # повеќе vertical padding надвор од box

for i, s in enumerate(config["ScheduledScripts"], start=1):
    # Земи само името на фајлот, без цел path
    script_name = os.path.basename(s["Path"])
    display_text = f"{i}. {script_name}"
    script_listbox.insert("end", display_text)
    # Случајна боја за текст
    r = random.randint(100, 255)
    g = random.randint(100, 255)
    b = random.randint(100, 255)
    color_hex = f"#{r:02X}{g:02X}{b:02X}"
    script_listbox.itemconfig("end", foreground=color_hex)
    
script_listbox.bind("<Button-1>", select_script)

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

# --- Headers ---
headers_frame = tk.Frame(scrollable_frame, bg="#1E1E1E")
headers_frame.pack(fill="x", pady=(0,5))
header_font = ("Segoe UI", 14, "bold")
tk.Label(headers_frame, text="#", width=4, bg="#1E1E1E", fg="#FFD700", font=header_font).pack(side="left", padx=0)
tk.Label(headers_frame, text="Command", width=10, bg="#1E1E1E", fg="#FFD700", font=header_font).pack(side="left", padx=(0,0))
tk.Label(headers_frame, text="Time (HH:MM:SS)", width=20, bg="#1E1E1E", fg="#00FF00", font=header_font).pack(side="left", padx=(5,0))
tk.Label(headers_frame, text="Delay Sec", width=10, bg="#1E1E1E", fg="#FF69B4", font=header_font).pack(side="left", padx=(0,10))
tk.Label(headers_frame, text="Repeat Min", width=10, bg="#1E1E1E", fg="#1E90FF", font=header_font).pack(side="left", padx=(0,10))
tk.Label(headers_frame, text="Select Date (YY:MM:DD)", width=20, bg="#1E1E1E", fg="#FF4500", font=header_font).pack(side="left", padx=(5,0))
tk.Label(headers_frame, text="Interval", width=10, bg="#1E1E1E", fg="#FF4500", font=header_font).pack(side="left", padx=(0,0))
tk.Label(headers_frame, text="Delete", width=10, bg="#1E1E1E", fg="#FF4500", font=header_font).pack(side="left", padx=(0,0))

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
        canvas.configure(scrollregion=canvas.bbox("all"))
        canvas.yview_moveto(0)
    else:
        if not v_scroll.winfo_ismapped():
            v_scroll.pack(side="right", fill="y")
        canvas.configure(scrollregion=(0,0,canvas.winfo_width(), content_height))
        canvas.configure(scrollregion=canvas.bbox("all"))
scrollable_frame.bind("<Configure>", on_frame_configure)

# --- Mousewheel scroll ---
def _on_mousewheel(event):
    # Scroll only if rows_frame has any children
    if rows_frame.winfo_children():
        content_height = canvas.bbox("all")[3] if canvas.bbox("all") else 0
        canvas_height = canvas.winfo_height()

        if content_height > canvas_height:
            canvas.yview_scroll(int(-1 * (event.delta // 120)), "units")

canvas.bind("<Enter>", lambda e: canvas.focus_set())
canvas.bind_all("<MouseWheel>", _on_mousewheel)

# --- Buttons frame ---
buttons_frame = tk.Frame(right_frame, bg="#1E1E1E")
buttons_frame.pack(pady=15, fill="x")  # fill x за центрирање  buttons_frame.pack(fill="x", side="top", pady=(10,0))

# --- Toast label (временски пораки) ---
status_label = ttk.Label(buttons_frame, text="", bootstyle="info", justify="center")
status_label.pack_forget()

# --- Status Label (Toast / Permanent Warning) ---
scripts_status_label = ttk.Label(buttons_frame, text="", bootstyle="info", justify="center")
scripts_status_label.pack_forget()  # start hidden

# --- Show temporary or permanent status messages ---
def show_status_message(message, style="info", duration=2000):
    scripts_status_label.config(text=message, bootstyle=style)
    scripts_status_label.pack(before=buttons_row, pady=(0,5))
    if duration is not None:
        scripts_status_label.after(duration, scripts_status_label.pack_forget)

# --- Add Row with status ---
def add_row_with_status():
    global config_dirty
    add_row()  # your existing add_row function
    config_dirty = True
    save_btn.config(state="normal")
    show_status_message("✔ Row added", "info", 1500)

# --- Save Config with status ---
def save_config_with_status():
    if current_script_index is None:
        save_all_config()  # save global config if no script selected
        show_status_message("✔ Global configuration saved", "success", 3000)
    else:
        save_config()  # save current script
        show_status_message("✔ Script configuration saved", "success", 3000)

# --- Update buttons & status based on script selection ---
def update_status_no_selection():
    if current_script_index is None:
        show_status_message(
            "⚠️ Select a SCRIPT first, then edit selected SCRIPT!",
            style="warning",
            duration=None  # stays until selection
        )
        add_btn.config(state="disabled")
        save_btn.config(state="disabled")
        default_btn.config(state="disabled")
    else:
        scripts_status_label.pack_forget()
        add_btn.config(state="normal")
        save_btn.config(state="normal")
        default_btn.config(state="normal")

# --- Buttons Row (Horizontally Centered) ---
buttons_row = tk.Frame(buttons_frame, bg="#1E1E1E")
buttons_row.pack(anchor="center")  # center horizontally

# --- Buttons ---
add_btn = ttk.Button(buttons_row, text="Add Row", bootstyle="info", command=add_row_with_status, state="disabled")
add_btn.pack(side="left", padx=20)

save_btn = ttk.Button(buttons_row, text="Save Config", bootstyle="success", command=save_config_with_status, state="disabled")
save_btn.pack(side="left", padx=20)

default_btn = ttk.Button(buttons_row, text="Default", bootstyle="warning", command=reset_to_default, state="disabled")
default_btn.pack(side="left", padx=20)

list_btn = ttk.Button(buttons_row, text="List All", bootstyle="info", command=open_json_table) 
list_btn.pack(side="left", padx=20)

reset_all_btn = ttk.Button(buttons_row, text="Reset All", bootstyle="danger", command=reset_all_scripts)
reset_all_btn.pack(side="left", padx=20)

update_status_no_selection()

# --- Долна линија текст, секогаш видлива ---
buttons_info_label = ttk.Label(
    buttons_frame,
    text="You can add up to 35 rows. Save Config and Default USE for every SCRIPTS separately.",
    bootstyle="secondary",
    justify="center",
    font=("Segoe UI", 11)
)
buttons_info_label.pack(side="bottom", pady=(15,0))  # најдолу

screen_width = root.winfo_screenwidth()
if screen_width < 1600:
    h_scroll = tk.Scrollbar(
        right_frame,
        orient="horizontal",
        command=canvas.xview,
        bg="#2C2C2C",        # track позадина
        troughcolor="#1E1E1E",  # trough позадина
        activebackground="#555555", # кога hover
        width=13             # тенка линија
    )
    canvas.configure(xscrollcommand=h_scroll.set)
    h_scroll.pack(fill="x", side="bottom")

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
            # Ако има селектирана скрипта → зачувај ја во config
            if current_script_index is not None:
                save_config()

            # Секогаш зачувај го целиот config во JSON
            save_all_config()

    root.destroy()
    
root.protocol("WM_DELETE_WINDOW", on_close)
root.mainloop()

################################################################################################################### End ScripsEditor.


############  PIP Install  ##############
# pip install ttkbootstrap pillow


############ .EXE COMPYLER  Install  ##############
# pip install pyinstaller ttkbootstrap pillow ZA.EXE FILE COMPILER

# python -m pip install --upgrade pip setuptools wheel  ZA.EXE FILE COMPILER

# python -m pip install pyinstaller  ZA.EXE FILE COMPILER

# pyinstaller --noconsole --onefile --windowed --add-data "media;media" --add-data "JSON;JSON" CommandsEditor.py  - CommandsEditor.exe

# pyinstaller --noconsole --onefile --windowed --add-data "media;media" --add-data "JSON;JSON" ScriptsEditor.py  - ScriptsEditor.exe

# pyinstaller --noconsole --onefile Camera.py  - Camera.exe
