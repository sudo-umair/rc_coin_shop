(function () {
    'use strict';

    const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'rc_coin_shop';

    async function post(name, data) {
        try {
            const res = await fetch(`https://${RES}/${name}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data || {}),
            });
            return await res.json();
        } catch (e) {
            return null;
        }
    }

    const $ = (sel) => document.querySelector(sel);
    const $$ = (sel) => Array.from(document.querySelectorAll(sel));

    // ---- state ----
    const state = {
        currency: 'Coins',
        maxQuantity: 100,
        balance: 0,
        isAdmin: false,
        items: [],
        activeCategory: 'All',
        search: '',
    };
    const admin = {
        items: [],
        oxItems: [],
        editingId: null,
        selectedTarget: null,
        coinMode: 'add',
    };
    let qtyItem = null;

    // ============================================================
    //  BRANDING
    // ============================================================
    function applyBranding(b) {
        if (!b) return;
        const root = document.documentElement.style;
        if (b.accent) root.setProperty('--accent', b.accent);
        if (b.accentHover) root.setProperty('--accent-hover', b.accentHover);
        $('#brandServer').textContent = b.serverName || 'Server';
        if (b.logo) {
            $('#brandLogo').src = b.logo;
            $$('.balance-coin').forEach((img) => (img.src = b.logo));
            root.setProperty('--watermark', `url("${b.logo}")`);
        }
        $('.panel').classList.toggle('watermark', !!b.showBackgroundLogo);
    }

    // ============================================================
    //  OPEN / CLOSE
    // ============================================================
    function openUI(data) {
        state.currency = data.currency || 'Coins';
        state.maxQuantity = data.maxQuantity || 100;
        state.balance = data.balance || 0;
        state.isAdmin = !!data.isAdmin;
        state.items = data.items || [];
        state.activeCategory = 'All';
        state.search = '';

        applyBranding(data.branding);
        $('#brandTitle').textContent = data.title || 'Coin Shop';
        $('#currencyLabel').textContent = state.currency;
        $('#shopSearch').value = '';
        updateBalance(state.balance);

        $('#adminTabBtn').classList.toggle('hidden', !state.isAdmin);
        switchTab('shop');
        renderCategories();
        renderShop();

        $('#app').classList.remove('hidden');
    }

    function closeUI() {
        $('#app').classList.add('hidden');
        $('#qtyModal').classList.add('hidden');
        $('#itemModal').classList.add('hidden');
    }

    function requestClose() {
        closeUI();
        post('close', {});
    }

    function updateBalance(v) {
        state.balance = v;
        $('#balance').textContent = Number(v).toLocaleString();
    }

    // ============================================================
    //  TABS
    // ============================================================
    function switchTab(tab) {
        $$('.tab').forEach((b) => b.classList.toggle('active', b.dataset.tab === tab));
        $$('.tab-panel').forEach((p) => p.classList.toggle('active', p.id === `tab-${tab}`));
        if (tab === 'admin') loadAdmin();
    }

    function switchSubtab(sub) {
        $$('.subtab').forEach((b) => b.classList.toggle('active', b.dataset.subtab === sub));
        $$('.subtab-panel').forEach((p) => p.classList.toggle('active', p.id === `subtab-${sub}`));
        if (sub === 'coins') searchPlayers('');
    }

    // ============================================================
    //  SHOP RENDER
    // ============================================================
    function categories() {
        const set = new Set(state.items.map((i) => i.category || 'General'));
        return ['All', ...Array.from(set).sort()];
    }

    function renderCategories() {
        const wrap = $('#categoryChips');
        wrap.innerHTML = '';
        categories().forEach((cat) => {
            const chip = document.createElement('div');
            chip.className = 'chip' + (cat === state.activeCategory ? ' active' : '');
            chip.textContent = cat;
            chip.onclick = () => {
                state.activeCategory = cat;
                renderCategories();
                renderShop();
            };
            wrap.appendChild(chip);
        });
    }

    function renderShop() {
        const grid = $('#shopGrid');
        grid.innerHTML = '';

        const q = state.search.toLowerCase();
        const filtered = state.items.filter((i) => {
            const inCat = state.activeCategory === 'All' || (i.category || 'General') === state.activeCategory;
            const inSearch = !q || i.label.toLowerCase().includes(q) || i.name.toLowerCase().includes(q);
            return inCat && inSearch;
        });

        $('#shopEmpty').classList.toggle('hidden', filtered.length > 0);

        filtered.forEach((item) => {
            const card = document.createElement('div');
            card.className = 'card';
            card.innerHTML = `
                <img class="card-img" src="${item.image}" onerror="this.style.visibility='hidden'" />
                <span class="card-cat">${esc(item.category || 'General')}</span>
                <span class="card-label">${esc(item.label)}</span>
                <span class="card-desc">${esc(item.description || '')}</span>
                <div class="card-foot">
                    <span class="card-price">${item.price.toLocaleString()} <small>${esc(state.currency)}</small></span>
                    <button class="btn primary small">Buy</button>
                </div>`;
            card.querySelector('button').onclick = () => openQtyModal(item);
            grid.appendChild(card);
        });
    }

    // ============================================================
    //  PURCHASE
    // ============================================================
    function openQtyModal(item) {
        qtyItem = item;
        $('#qtyImage').src = item.image;
        $('#qtyLabel').textContent = item.label;
        $('#qtyUnit').textContent = `${item.price.toLocaleString()} ${state.currency} each`;
        $('#qtyInput').value = 1;
        $('#qtyInput').max = state.maxQuantity;
        updateQtyTotal();
        $('#qtyModal').classList.remove('hidden');
    }

    function clampQty(v) {
        v = parseInt(v, 10);
        if (isNaN(v) || v < 1) v = 1;
        if (v > state.maxQuantity) v = state.maxQuantity;
        return v;
    }

    function updateQtyTotal() {
        const qty = clampQty($('#qtyInput').value);
        $('#qtyTotal').textContent = (qty * (qtyItem ? qtyItem.price : 0)).toLocaleString();
    }

    async function confirmPurchase() {
        if (!qtyItem) return;
        const qty = clampQty($('#qtyInput').value);
        const btn = $('#qtyConfirm');
        btn.disabled = true;
        const result = await post('purchase', { name: qtyItem.name, quantity: qty });
        btn.disabled = false;

        if (result) {
            toast(result.success ? 'success' : 'error', result.message);
            if (result.success) {
                if (typeof result.balance === 'number') updateBalance(result.balance);
                $('#qtyModal').classList.add('hidden');
            }
        }
    }

    // ============================================================
    //  ADMIN - ITEMS
    // ============================================================
    async function loadAdmin() {
        const data = await post('admin:getItems', {});
        if (!data) return;
        admin.items = data.items || [];
        admin.oxItems = data.oxItems || [];

        // Populate the item picker dropdown, sorted by label.
        const sel = $('#fName');
        const opts = admin.oxItems
            .slice()
            .sort((a, b) => String(a.label).localeCompare(String(b.label)))
            .map((i) => `<option value="${esc(i.name)}">${esc(i.label)} (${esc(i.name)})</option>`)
            .join('');
        sel.innerHTML = `<option value="" disabled selected>Select an item…</option>` + opts;

        renderAdminItems();
    }

    // Select an item in the dropdown, adding a fallback option if the item is
    // no longer registered in ox_inventory (so editing an old entry still shows it).
    function setItemSelect(name) {
        const sel = $('#fName');
        if (name && !Array.from(sel.options).some((o) => o.value === name)) {
            const o = document.createElement('option');
            o.value = name;
            o.textContent = `${name} (missing from ox_inventory)`;
            sel.appendChild(o);
        }
        sel.value = name || '';
    }

    function renderAdminItems() {
        const list = $('#adminItemList');
        list.innerHTML = '';
        if (!admin.items.length) {
            list.innerHTML = '<div class="empty">Catalog is empty. Click “Add Item” to start.</div>';
            return;
        }
        admin.items.forEach((item) => {
            const row = document.createElement('div');
            row.className = 'row-item';
            row.innerHTML = `
                <img src="${item.image}" onerror="this.style.visibility='hidden'" />
                <div class="ri-main">
                    <div class="ri-label">${esc(item.label)}
                        <span class="badge ${item.enabled ? 'on' : 'off'}">${item.enabled ? 'Enabled' : 'Hidden'}</span>
                    </div>
                    <div class="ri-sub">${esc(item.name)} • ${esc(item.category || 'General')}</div>
                </div>
                <span class="ri-price">${item.price.toLocaleString()}</span>
                <button class="btn ghost small">Edit</button>`;
            row.querySelector('button').onclick = () => openItemForm(item);
            list.appendChild(row);
        });
    }

    function openItemForm(item) {
        admin.editingId = item ? item.id : null;
        $('#itemModalTitle').textContent = item ? 'Edit Item' : 'Add Item';
        setItemSelect(item ? item.name : '');
        $('#fName').disabled = !!item; // name is the unique key; don't rename in place
        $('#fPrice').value = item ? item.price : 0;
        $('#fLabel').value = item ? (item.rawLabel || '') : '';
        $('#fLabel').placeholder = item ? item.label : 'Defaults to ox_inventory label';
        $('#fCategory').value = item ? (item.rawCategory || '') : '';
        $('#fDescription').value = item ? (item.description || '') : '';
        $('#fImage').value = item ? (item.rawImage || '') : '';
        $('#fSort').value = item ? (item.sort_order || 0) : 0;
        $('#fEnabled').checked = item ? !!item.enabled : true;
        $('#itemDelete').classList.toggle('hidden', !item);
        $('#itemModal').classList.remove('hidden');
    }

    async function saveItem() {
        const payload = {
            id: admin.editingId || undefined,
            name: $('#fName').value.trim(),
            price: parseInt($('#fPrice').value, 10) || 0,
            label: $('#fLabel').value.trim(),
            category: $('#fCategory').value.trim(),
            description: $('#fDescription').value.trim(),
            image: $('#fImage').value.trim(),
            sort_order: parseInt($('#fSort').value, 10) || 0,
            enabled: $('#fEnabled').checked,
        };
        const btn = $('#itemSave');
        btn.disabled = true;
        const result = await post('admin:saveItem', payload);
        btn.disabled = false;
        if (!result) return;
        toast(result.success ? 'success' : 'error', result.message);
        if (result.success) {
            admin.items = result.items || admin.items;
            renderAdminItems();
            $('#itemModal').classList.add('hidden');
        }
    }

    async function deleteItem() {
        if (!admin.editingId) return;
        const result = await post('admin:deleteItem', { id: admin.editingId });
        if (!result) return;
        toast(result.success ? 'success' : 'error', result.message);
        if (result.success) {
            admin.items = result.items || admin.items;
            renderAdminItems();
            $('#itemModal').classList.add('hidden');
        }
    }

    // ============================================================
    //  ADMIN - COINS
    // ============================================================
    let playerSearchTimer = null;

    async function searchPlayers(term) {
        const res = await post('admin:getPlayers', { search: term || '' });
        const list = $('#playerList');
        const countEl = $('#playerCount');
        list.innerHTML = '';

        const players = (res && res.players) || [];
        if (countEl) {
            countEl.textContent = players.length
                ? (res.capped ? `(showing ${players.length}+)` : `(${players.length})`)
                : '';
        }

        if (!players.length) {
            list.innerHTML = '<div class="empty">No matching players found.</div>';
            return;
        }

        players.forEach((p) => {
            const row = document.createElement('div');
            row.className = 'row-item selectable' + (admin.selectedTarget === String(p.target) ? ' selected' : '');

            const ids = (p.identifiers || [])
                .map((i) => `<span class="id-chip id-${esc(i.kind)}">${esc(i.kind)}: ${esc(i.value)}</span>`)
                .join('');

            const meta = [
                p.online ? `<span class="muted">[${p.id}]</span>` : '',
                p.characters > 1 ? `<span class="muted">${p.characters} chars</span>` : '',
            ].filter(Boolean).join(' ');

            row.innerHTML = `
                <span class="dot ${p.online ? 'on' : 'off'}" title="${p.online ? 'Online' : 'Offline'}"></span>
                <div class="ri-main">
                    <div class="ri-label">${esc(p.name)} ${meta}</div>
                    <div class="id-chips">${ids || '<span class="muted">no stored identifiers</span>'}</div>
                </div>
                <span class="ri-price">${Number(p.balance).toLocaleString()}</span>`;
            row.onclick = () => {
                admin.selectedTarget = String(p.target);
                $('#coinTarget').value = String(p.target);
                $$('#playerList .row-item').forEach((r) => r.classList.remove('selected'));
                row.classList.add('selected');
            };
            list.appendChild(row);
        });
    }

    async function applyCoins() {
        const target = $('#coinTarget').value.trim();
        const amount = parseInt($('#coinAmount').value, 10);
        if (!target) return toast('error', 'Enter or select a target.');
        if (isNaN(amount) || amount < 0) return toast('error', 'Enter a valid amount.');

        const btn = $('#applyCoinsBtn');
        btn.disabled = true;
        const result = await post('admin:modifyCoins', { target, mode: admin.coinMode, amount });
        btn.disabled = false;
        if (!result) return;
        toast(result.success ? 'success' : 'error', result.message);
        if (result.success) searchPlayers($('#playerSearch').value); // refresh balances
    }

    // ============================================================
    //  TOASTS
    // ============================================================
    function toast(type, message) {
        if (!message) return;
        const el = document.createElement('div');
        el.className = `toast ${type || 'inform'}`;
        el.textContent = message;
        $('#toasts').appendChild(el);
        setTimeout(() => {
            el.classList.add('fade');
            setTimeout(() => el.remove(), 300);
        }, 3200);
    }

    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({
            '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
        }[c]));
    }

    // ============================================================
    //  EVENTS
    // ============================================================
    window.addEventListener('message', (e) => {
        const { action, data } = e.data || {};
        if (action === 'open') openUI(data);
        else if (action === 'close') closeUI();
        else if (action === 'toast') toast(data.type, data.message);
        else if (action === 'setBalance') updateBalance(data.balance);
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
            if (!$('#qtyModal').classList.contains('hidden')) return $('#qtyModal').classList.add('hidden');
            if (!$('#itemModal').classList.contains('hidden')) return $('#itemModal').classList.add('hidden');
            requestClose();
        }
    });

    // delegated clicks for close targets
    $$('[data-close]').forEach((el) => (el.onclick = requestClose));

    // tabs
    $$('.tab').forEach((b) => (b.onclick = () => switchTab(b.dataset.tab)));
    $$('.subtab').forEach((b) => (b.onclick = () => switchSubtab(b.dataset.subtab)));

    // shop search
    $('#shopSearch').addEventListener('input', (e) => {
        state.search = e.target.value;
        renderShop();
    });

    // qty modal
    $('#qtyMinus').onclick = () => { $('#qtyInput').value = clampQty($('#qtyInput').value) - 1 || 1; updateQtyTotal(); };
    $('#qtyPlus').onclick = () => { $('#qtyInput').value = clampQty(parseInt($('#qtyInput').value, 10) + 1); updateQtyTotal(); };
    $('#qtyInput').addEventListener('input', updateQtyTotal);
    $('#qtyCancel').onclick = () => $('#qtyModal').classList.add('hidden');
    $('#qtyConfirm').onclick = confirmPurchase;

    // item editor
    $('#addItemBtn').onclick = () => openItemForm(null);
    $('#itemCancel').onclick = () => $('#itemModal').classList.add('hidden');
    $('#itemSave').onclick = saveItem;
    $('#itemDelete').onclick = deleteItem;

    // coins
    $('#playerSearch').addEventListener('input', (e) => {
        clearTimeout(playerSearchTimer);
        const v = e.target.value;
        playerSearchTimer = setTimeout(() => searchPlayers(v), 200);
    });
    $$('#coinMode .seg-btn').forEach((b) => (b.onclick = () => {
        admin.coinMode = b.dataset.mode;
        $$('#coinMode .seg-btn').forEach((x) => x.classList.toggle('active', x === b));
    }));
    $('#applyCoinsBtn').onclick = applyCoins;
})();
