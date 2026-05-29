package pt.meshcore.lusoapp

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.StateListDrawable
import android.os.Bundle
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.SeekBar
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.google.android.flexbox.FlexboxLayout
import com.google.android.material.appbar.MaterialToolbar
import com.google.android.material.button.MaterialButton
import com.google.android.material.checkbox.MaterialCheckBox
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.materialswitch.MaterialSwitch

class WidgetConfigActivity : AppCompatActivity() {

    private var widgetId = AppWidgetManager.INVALID_APPWIDGET_ID

    private val swatches = listOf(
        0xFFFF6B00.toInt(), // brand orange (default)
        0xFFB3261E.toInt(), // red
        0xFFF59E0B.toInt(), // amber
        0xFF84CC16.toInt(), // lime
        0xFF10B981.toInt(), // emerald
        0xFF06B6D4.toInt(), // cyan
        0xFF3B82F6.toInt(), // blue
        0xFF6366F1.toInt(), // indigo
        0xFF8B5CF6.toInt(), // violet
        0xFFEC4899.toInt(), // pink
        0xFF6B7280.toInt(), // neutral
    )

    private lateinit var rows: MutableList<ButtonRow>
    private var selectedAccent = WidgetConfig.DEFAULT_ACCENT

    private data class ButtonRow(
        val key: String,
        var checked: Boolean,
        var showLabel: Boolean,
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Default cancel — dismissing without saving must not leave a placed widget.
        setResult(RESULT_CANCELED)

        widgetId = intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

        if (widgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }

        setContentView(R.layout.activity_widget_config)
        setSupportActionBar(findViewById<MaterialToolbar>(R.id.config_toolbar))

        val current = WidgetConfig.load(this, widgetId)
        selectedAccent = current.accent

        // Seed the row list: selected items first (in saved order),
        // then unselected items in canonical order.
        val selectedKeys = current.buttons
        val rest = WidgetConfig.ALL_BUTTONS.filter { it !in selectedKeys }
        rows = (selectedKeys.map { ButtonRow(it, true,  it in current.labels) } +
                rest.map         { ButtonRow(it, false, it in current.labels) }
               ).toMutableList()

        setupButtonsList()
        setupSwatches()
        wireSaveCancel()
    }

    private fun setupButtonsList() {
        val rv = findViewById<RecyclerView>(R.id.config_buttons_list)
        rv.layoutManager = LinearLayoutManager(this)
        val adapter = ButtonAdapter()
        rv.adapter = adapter

        val touchHelper = ItemTouchHelper(object : ItemTouchHelper.SimpleCallback(
            ItemTouchHelper.UP or ItemTouchHelper.DOWN, 0,
        ) {
            override fun onMove(
                rv: RecyclerView,
                src: RecyclerView.ViewHolder,
                dst: RecyclerView.ViewHolder,
            ): Boolean {
                val from = src.bindingAdapterPosition
                val to = dst.bindingAdapterPosition
                // Only allow reordering within the "selected" prefix.
                if (!rows[from].checked || !rows[to].checked) return false
                val moved = rows.removeAt(from)
                rows.add(to, moved)
                adapter.notifyItemMoved(from, to)
                return true
            }

            override fun onSwiped(vh: RecyclerView.ViewHolder, dir: Int) = Unit
        })
        touchHelper.attachToRecyclerView(rv)
        adapter.touchHelper = touchHelper
    }

    private fun setupSwatches() {
        val container = findViewById<FlexboxLayout>(R.id.config_swatches)
        container.removeAllViews()

        for (color in swatches) {
            container.addView(makeSwatch(color, isCustom = false))
        }
        container.addView(makeCustomTile())
        refreshSwatchSelection()
    }

    private fun makeSwatch(color: Int, isCustom: Boolean): View {
        val density = resources.displayMetrics.density
        val size    = (density * 40).toInt()
        val margin  = (density * 6).toInt()
        val ringPx  = (density * 3).toInt()

        return ImageView(this).apply {
            layoutParams = ViewGroup.MarginLayoutParams(size, size).apply {
                setMargins(margin, margin, margin, margin)
            }
            background = makeSwatchDrawable(color, ringPx)
            isClickable = true
            isFocusable = true
            tag = color
            contentDescription = "#%06X".format(0xFFFFFF and color)
            setOnClickListener {
                selectedAccent = color
                refreshSwatchSelection()
            }
        }
    }

    private fun makeSwatchDrawable(color: Int, ringPx: Int): StateListDrawable {
        val ringColor = resources.getColor(android.R.color.darker_gray, theme)

        val unselected = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
        }
        val selected = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(color)
            setStroke(ringPx, ringColor)
        }
        return StateListDrawable().apply {
            addState(intArrayOf(android.R.attr.state_selected), selected)
            addState(intArrayOf(), unselected)
        }
    }

    private fun makeCustomTile(): View {
        val density = resources.displayMetrics.density
        val height  = (density * 40).toInt()
        val margin  = (density * 6).toInt()

        return MaterialButton(
            this, null, com.google.android.material.R.attr.materialButtonOutlinedStyle,
        ).apply {
            layoutParams = ViewGroup.MarginLayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, height,
            ).apply {
                setMargins(margin, margin, margin, margin)
            }
            text = getString(R.string.widget_config_custom_color)
            cornerRadius = height / 2
            insetTop = 0
            insetBottom = 0
            setOnClickListener { showCustomColorDialog() }
        }
    }

    private fun refreshSwatchSelection() {
        val container = findViewById<FlexboxLayout>(R.id.config_swatches)
        for (i in 0 until container.childCount) {
            val child = container.getChildAt(i)
            val tag = child.tag as? Int ?: continue
            child.isSelected = (tag == selectedAccent)
        }
    }

    private fun showCustomColorDialog() {
        val ctx = this
        val container = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(48, 32, 48, 16)
        }
        val preview = View(ctx).apply {
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, 80,
            )
            setBackgroundColor(selectedAccent)
        }
        container.addView(preview)

        val r = SeekBar(ctx).apply { max = 255; progress = Color.red(selectedAccent) }
        val g = SeekBar(ctx).apply { max = 255; progress = Color.green(selectedAccent) }
        val b = SeekBar(ctx).apply { max = 255; progress = Color.blue(selectedAccent) }

        val sync = object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(s: SeekBar?, p: Int, fromUser: Boolean) {
                    preview.setBackgroundColor(
                        Color.argb(0xFF, r.progress, g.progress, b.progress),
                    )
                }
                override fun onStartTrackingTouch(s: SeekBar?) = Unit
                override fun onStopTrackingTouch(s: SeekBar?) = Unit
        }
        r.setOnSeekBarChangeListener(sync)
        g.setOnSeekBarChangeListener(sync)
        b.setOnSeekBarChangeListener(sync)

        for ((label, sb) in listOf("R" to r, "G" to g, "B" to b)) {
            container.addView(TextView(ctx).apply { text = label })
            container.addView(sb)
        }

        MaterialAlertDialogBuilder(ctx)
            .setTitle(R.string.widget_config_custom_color)
            .setView(container)
            .setPositiveButton(R.string.widget_config_save) { _, _ ->
                selectedAccent = Color.argb(
                    0xFF, r.progress, g.progress, b.progress,
                )
                refreshSwatchSelection()
            }
            .setNegativeButton(R.string.widget_config_cancel, null)
            .show()
    }

    private fun wireSaveCancel() {
        findViewById<MaterialButton>(R.id.config_cancel).setOnClickListener {
            finish() // result is already RESULT_CANCELED
        }
        findViewById<MaterialButton>(R.id.config_save).setOnClickListener {
            val selected = rows.filter { it.checked }.map { it.key }
            if (selected.size !in WidgetConfig.MIN_BUTTONS..WidgetConfig.MAX_BUTTONS) {
                MaterialAlertDialogBuilder(this)
                    .setMessage(
                        "Escolhe entre ${WidgetConfig.MIN_BUTTONS} e " +
                        "${WidgetConfig.MAX_BUTTONS} botões.",
                    )
                    .setPositiveButton(android.R.string.ok, null)
                    .show()
                return@setOnClickListener
            }
            // Only labels for selected buttons are persisted.
            val labels = rows.filter { it.checked && it.showLabel }.map { it.key }.toSet()
            WidgetConfig.save(
                this, widgetId,
                WidgetConfig(buttons = selected, labels = labels, accent = selectedAccent),
            )
            val mgr = AppWidgetManager.getInstance(this)
            MeshCoreWidgetProvider.updateWidget(this, mgr, widgetId)

            val result = Intent().putExtra(
                AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId,
            )
            setResult(RESULT_OK, result)
            finish()
        }
    }

    // ----- adapter -----

    private inner class ButtonAdapter : RecyclerView.Adapter<ButtonAdapter.VH>() {
        var touchHelper: ItemTouchHelper? = null

        inner class VH(view: View) : RecyclerView.ViewHolder(view) {
            val check: MaterialCheckBox   = view.findViewById(R.id.pick_check)
            val icon: ImageView           = view.findViewById(R.id.pick_icon)
            val label: TextView           = view.findViewById(R.id.pick_label)
            val labelSwitch: MaterialSwitch = view.findViewById(R.id.pick_label_toggle)
            val drag: ImageView           = view.findViewById(R.id.pick_drag)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
            val v = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_widget_button_pick, parent, false)
            return VH(v)
        }

        override fun getItemCount() = rows.size

        override fun onBindViewHolder(h: VH, position: Int) {
            val row = rows[position]
            h.icon.setImageResource(iconResFor(row.key))
            h.label.setText(labelResFor(row.key))
            h.check.setOnCheckedChangeListener(null)
            h.check.isChecked = row.checked
            h.check.setOnCheckedChangeListener { _, isChecked ->
                row.checked = isChecked
                // Re-partition: keep selected rows above unselected rows so
                // drag-reorder stays bounded to the selected prefix.
                rows.sortByDescending { it.checked }
                notifyDataSetChanged()
            }

            h.labelSwitch.setOnCheckedChangeListener(null)
            h.labelSwitch.isChecked = row.showLabel
            h.labelSwitch.visibility = if (row.checked) View.VISIBLE else View.GONE
            h.labelSwitch.setOnCheckedChangeListener { _, isChecked ->
                row.showLabel = isChecked
            }

            h.drag.visibility = if (row.checked) View.VISIBLE else View.GONE
            h.drag.setOnTouchListener { _, ev ->
                if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
                    touchHelper?.startDrag(h)
                }
                false
            }
        }

        private fun iconResFor(key: String) = when (key) {
            "sos"       -> R.drawable.ic_widget_warning
            "advert"    -> R.drawable.ic_widget_broadcast
            "connect"   -> R.drawable.ic_widget_power
            "chats"     -> R.drawable.ic_widget_chat
            "map"       -> R.drawable.ic_widget_map
            "plan333"   -> R.drawable.ic_widget_plan333
            "telemetry" -> R.drawable.ic_widget_telemetry
            else        -> R.drawable.ic_widget_power
        }

        private fun labelResFor(key: String) = when (key) {
            "sos"       -> R.string.widget_btn_sos
            "advert"    -> R.string.widget_btn_advert
            "connect"   -> R.string.widget_btn_connect
            "chats"     -> R.string.widget_btn_chats
            "map"       -> R.string.widget_btn_map
            "plan333"   -> R.string.widget_btn_plan333
            "telemetry" -> R.string.widget_btn_telemetry
            else        -> R.string.widget_btn_connect
        }
    }
}
