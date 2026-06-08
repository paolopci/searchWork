(function () {
    'use strict';

    let data = { state: { companies: [] }, queries: [], profile: { queries: [] } };
    let companies = [];
    let queries = [];
    let profileQueries = [];
    let categoryChart = null;
    let skillsChart = null;

    const elements = {
        toast: document.getElementById('toast'),
        totalCompanies: document.getElementById('totalCompanies'),
        companiesWithWebsite: document.getElementById('companiesWithWebsite'),
        totalQueries: document.getElementById('totalQueries'),
        stateUpdatedAt: document.getElementById('stateUpdatedAt'),
        lastUpdatedCompact: document.getElementById('lastUpdatedCompact'),
        textFilter: document.getElementById('textFilter'),
        skillFilter: document.getElementById('skillFilter'),
        categoryFilter: document.getElementById('categoryFilter'),
        websiteFilter: document.getElementById('websiteFilter'),
        resetFilters: document.getElementById('resetFilters'),
        resultSummary: document.getElementById('resultSummary'),
        companiesTable: document.getElementById('companiesTable'),
        emptyState: document.getElementById('emptyState'),
        tableWrap: document.getElementById('tableWrap'),
        queriesList: document.getElementById('queriesList'),
        refreshDashboard: document.getElementById('refreshDashboard'),
        addCompanyTop: document.getElementById('addCompanyTop'),
        addQuery: document.getElementById('addQuery'),
        companyModal: document.getElementById('companyModal'),
        companyForm: document.getElementById('companyForm'),
        companyFormTitle: document.getElementById('companyFormTitle'),
        companyId: document.getElementById('companyId'),
        companyName: document.getElementById('companyName'),
        companyWebsite: document.getElementById('companyWebsite'),
        companyPerson: document.getElementById('companyPerson'),
        companyProfileUrl: document.getElementById('companyProfileUrl'),
        companySkills: document.getElementById('companySkills'),
        companySearchQuery: document.getElementById('companySearchQuery'),
        companyNotes: document.getElementById('companyNotes'),
        queryModal: document.getElementById('queryModal'),
        queryForm: document.getElementById('queryForm'),
        queryFormTitle: document.getElementById('queryFormTitle'),
        queryId: document.getElementById('queryId'),
        queryCategory: document.getElementById('queryCategory'),
        queryPriority: document.getElementById('queryPriority'),
        queryTerms: document.getElementById('queryTerms'),
        queryEnabled: document.getElementById('queryEnabled'),
        queryPreview: document.getElementById('queryPreview')
    };

    function normalize(value) {
        return String(value || '').trim().toLowerCase();
    }

    function escapeHtml(value) {
        return String(value || '')
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#039;');
    }

    function formatDate(value) {
        if (!value) {
            return '-';
        }
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) {
            return value;
        }
        return new Intl.DateTimeFormat('it-IT', {
            dateStyle: 'short',
            timeStyle: 'short'
        }).format(date);
    }

    function splitValues(value) {
        return String(value || '')
            .split(';')
            .map((item) => item.trim())
            .filter(Boolean);
    }

    function buildQueryText(terms) {
        const cleanTerms = Array.isArray(terms) ? terms : splitValues(terms);
        return ['site:linkedin.com/in'].concat(cleanTerms.map((term) => `"${term}"`)).join(' ');
    }

    function getWebsiteUrl(value) {
        const raw = String(value || '').trim();
        if (!raw) {
            return '';
        }
        return /^[a-z][a-z0-9+\-.]*:\/\//i.test(raw) ? raw : `https://${raw}`;
    }

    function getQueryByText() {
        return new Map(
            queries
                .filter((query) => query.Query)
                .map((query) => [normalize(query.Query), query])
        );
    }

    function getCompanyCategory(company) {
        const query = getQueryByText().get(normalize(company.SearchQuery));
        return query ? query.Category : 'Non classificata';
    }

    function showToast(message, type) {
        elements.toast.textContent = message;
        elements.toast.className = `mb-4 rounded-md border px-4 py-3 text-sm ${type === 'error'
            ? 'border-red-200 bg-red-50 text-red-700'
            : 'border-emerald-200 bg-emerald-50 text-emerald-700'}`;
        elements.toast.classList.remove('hidden');
        window.setTimeout(() => elements.toast.classList.add('hidden'), 4500);
    }

    async function api(path, options) {
        const response = await fetch(path, {
            headers: { 'Content-Type': 'application/json' },
            ...options
        });
        const payload = await response.json();
        if (!response.ok || payload.ok === false) {
            throw new Error(payload.error || `Errore API ${response.status}`);
        }
        return payload;
    }

    async function loadDashboard() {
        data = await api('/api/dashboard');
        companies = Array.isArray(data.state?.companies)
            ? data.state.companies.filter((company) => !company.DeletedAt)
            : [];
        queries = Array.isArray(data.queries) ? data.queries : [];
        profileQueries = Array.isArray(data.profile?.queries) ? data.profile.queries : [];
        renderAll();
    }

    function updateFromMutation(payload, message) {
        if (payload.dashboard) {
            data = payload.dashboard;
            companies = Array.isArray(data.state?.companies)
                ? data.state.companies.filter((company) => !company.DeletedAt)
                : [];
            queries = Array.isArray(data.queries) ? data.queries : [];
            profileQueries = Array.isArray(data.profile?.queries) ? data.profile.queries : [];
            renderAll();
        }
        showToast(message, 'success');
    }

    function setOptions(select, values, defaultLabel) {
        select.innerHTML = '';
        const defaultOption = document.createElement('option');
        defaultOption.value = 'all';
        defaultOption.textContent = defaultLabel;
        select.appendChild(defaultOption);

        values.forEach((value) => {
            const option = document.createElement('option');
            option.value = value;
            option.textContent = value;
            select.appendChild(option);
        });
    }

    function initializeFilters() {
        const selectedSkill = elements.skillFilter.value || 'all';
        const selectedCategory = elements.categoryFilter.value || 'all';
        const skills = [...new Set(companies.flatMap((company) => splitValues(company.MatchedSkills)))]
            .sort((a, b) => a.localeCompare(b, 'it', { sensitivity: 'base' }));
        const categories = [...new Set(queries.map((query) => query.Category).filter(Boolean))]
            .sort((a, b) => a.localeCompare(b, 'it', { sensitivity: 'base' }));

        if (companies.some((company) => !getQueryByText().has(normalize(company.SearchQuery)))) {
            categories.push('Non classificata');
        }

        setOptions(elements.skillFilter, skills, 'Tutte');
        setOptions(elements.categoryFilter, categories, 'Tutte');
        elements.skillFilter.value = skills.includes(selectedSkill) ? selectedSkill : 'all';
        elements.categoryFilter.value = categories.includes(selectedCategory) ? selectedCategory : 'all';
    }

    function updateKpis() {
        const withWebsite = companies.filter((company) => String(company.Website || '').trim()).length;
        const updatedAt = data.state?.generatedAt || data.generatedAt;
        elements.totalCompanies.textContent = companies.length;
        elements.companiesWithWebsite.textContent = withWebsite;
        elements.totalQueries.textContent = queries.length;
        elements.stateUpdatedAt.textContent = formatDate(updatedAt);
        elements.lastUpdatedCompact.textContent = `Aggiornato: ${formatDate(updatedAt)}`;
    }

    function countBy(items, selector) {
        return items.reduce((accumulator, item) => {
            const key = selector(item) || 'Non classificata';
            accumulator.set(key, (accumulator.get(key) || 0) + 1);
            return accumulator;
        }, new Map());
    }

    function resetChartCanvas(wrapperId, canvasId) {
        const wrapper = document.getElementById(wrapperId);
        wrapper.innerHTML = `<canvas id="${canvasId}"></canvas>`;
        return document.getElementById(canvasId);
    }

    function buildChart(wrapperId, canvasId, currentChart, type, labels, values, label, colors) {
        if (currentChart) {
            currentChart.destroy();
        }
        const canvas = resetChartCanvas(wrapperId, canvasId);
        if (!canvas || typeof Chart === 'undefined') {
            return null;
        }
        if (labels.length === 0) {
            canvas.parentElement.innerHTML = '<div class="flex h-full items-center justify-center rounded-md bg-slate-50 text-sm text-slate-500">Nessun dato disponibile</div>';
            return null;
        }
        return new Chart(canvas, {
            type,
            data: {
                labels,
                datasets: [{
                    label,
                    data: values,
                    backgroundColor: colors,
                    borderColor: colors,
                    borderWidth: 1
                }]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                plugins: {
                    legend: {
                        display: type !== 'bar',
                        labels: { boxWidth: 12, font: { size: 11 } }
                    }
                },
                scales: type === 'bar' ? { y: { beginAtZero: true, ticks: { precision: 0 } } } : {}
            }
        });
    }

    function renderCharts() {
        const palette = ['#0284c7', '#059669', '#7c3aed', '#d97706', '#dc2626', '#475569', '#0891b2', '#65a30d'];
        const categories = countBy(companies, getCompanyCategory);
        const skills = countBy(companies.flatMap((company) => splitValues(company.MatchedSkills)), (skill) => skill);
        const topSkills = [...skills.entries()]
            .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'it', { sensitivity: 'base' }))
            .slice(0, 10);

        categoryChart = buildChart('categoryChartWrap', 'categoryChart', categoryChart, 'doughnut', [...categories.keys()], [...categories.values()], 'Aziende', palette);
        skillsChart = buildChart('skillsChartWrap', 'skillsChart', skillsChart, 'bar', topSkills.map(([skill]) => skill), topSkills.map(([, count]) => count), 'Occorrenze', palette[0]);
    }

    function renderQueries() {
        if (profileQueries.length === 0) {
            elements.queriesList.innerHTML = '<div class="rounded-md bg-slate-50 p-4 text-sm text-slate-500">Nessuna query configurata.</div>';
            return;
        }

        const activeQueryById = new Map(queries.map((query) => [query.Id, query]));
        elements.queriesList.innerHTML = profileQueries.map((profileQuery) => {
            const active = activeQueryById.get(profileQuery.id);
            const terms = Array.isArray(profileQuery.terms) ? profileQuery.terms : [];
            const enabled = profileQuery.enabled !== false;
            const queryText = active ? active.Query : buildQueryText(terms);
            return `
                <article class="rounded-lg border border-slate-200 bg-white p-4 shadow-sm ${enabled ? '' : 'opacity-60'}">
                    <div class="mb-3 flex items-start justify-between gap-3">
                        <div>
                            <div class="font-semibold">${escapeHtml(profileQuery.category || '-')} <span class="text-sm font-normal text-slate-500">P${escapeHtml(profileQuery.priority || '-')}</span></div>
                            <div class="mt-1 text-xs text-slate-500">${enabled ? 'Abilitata' : 'Disabilitata'}</div>
                        </div>
                        <div class="flex flex-wrap justify-end gap-2">
                            <button data-open-query="${escapeHtml(profileQuery.id)}" type="button" class="rounded-md border border-slate-300 px-3 py-1.5 text-xs font-medium hover:bg-slate-100" ${enabled ? '' : 'disabled'}>Apri query</button>
                            <button data-company-from-query="${escapeHtml(profileQuery.id)}" type="button" class="rounded-md border border-slate-300 px-3 py-1.5 text-xs font-medium hover:bg-slate-100">Aggiungi azienda</button>
                            <button data-edit-query="${escapeHtml(profileQuery.id)}" type="button" class="rounded-md bg-slate-900 px-3 py-1.5 text-xs font-medium text-white hover:bg-slate-700">Edit query</button>
                        </div>
                    </div>
                    <div class="text-xs text-slate-600">
                        <div class="mb-2 flex flex-wrap gap-1">${terms.map((term) => `<span class="rounded bg-slate-100 px-2 py-1">${escapeHtml(term)}</span>`).join('')}</div>
                        <div class="font-mono">${escapeHtml(queryText)}</div>
                    </div>
                </article>
            `;
        }).join('');
    }

    function getFilteredCompanies() {
        const text = normalize(elements.textFilter.value);
        const selectedSkill = elements.skillFilter.value;
        const selectedCategory = elements.categoryFilter.value;
        const websiteMode = elements.websiteFilter.value;

        return companies.filter((company) => {
            const companySkills = splitValues(company.MatchedSkills);
            const category = getCompanyCategory(company);
            const hasWebsite = Boolean(String(company.Website || '').trim());
            const haystack = normalize([
                company.CompanyName,
                company.Website,
                company.SourcePersonName,
                company.SourceProfileUrl,
                company.MatchedSkills,
                company.SearchQuery,
                company.Notes
            ].join(' '));

            if (text && !haystack.includes(text)) return false;
            if (selectedSkill !== 'all' && !companySkills.some((skill) => skill.toLowerCase() === selectedSkill.toLowerCase())) return false;
            if (selectedCategory !== 'all' && category !== selectedCategory) return false;
            if (websiteMode === 'with' && !hasWebsite) return false;
            if (websiteMode === 'without' && hasWebsite) return false;
            return true;
        });
    }

    function renderSkillList(skills) {
        if (skills.length === 0) {
            return '<span class="text-slate-400">-</span>';
        }
        return skills
            .map((skill) => `<span class="inline-flex rounded bg-sky-50 px-2 py-1 text-xs font-medium text-sky-700">${escapeHtml(skill)}</span>`)
            .join(' ');
    }

    function renderTable() {
        const filtered = getFilteredCompanies();
        elements.resultSummary.textContent = `${filtered.length} aziende visualizzate su ${companies.length}`;
        elements.emptyState.classList.toggle('hidden', companies.length > 0);
        elements.tableWrap.classList.toggle('hidden', companies.length === 0);

        elements.companiesTable.innerHTML = filtered.map((company) => {
            const websiteUrl = getWebsiteUrl(company.Website);
            const query = getQueryByText().get(normalize(company.SearchQuery));
            const category = getCompanyCategory(company);
            const skills = splitValues(company.MatchedSkills);

            return `
                <tr class="align-top hover:bg-slate-50">
                    <td class="px-4 py-3">
                        <div class="font-medium text-slate-950">${escapeHtml(company.CompanyName || '-')}</div>
                        <div class="mt-1 text-xs text-slate-500">${escapeHtml(company.DedupKey || '')}</div>
                    </td>
                    <td class="px-4 py-3">
                        ${websiteUrl ? `<a class="font-medium text-sky-700 hover:underline" href="${escapeHtml(websiteUrl)}" target="_blank" rel="noreferrer">${escapeHtml(company.Website)}</a>` : '<span class="text-slate-400">-</span>'}
                    </td>
                    <td class="px-4 py-3">
                        <div>${escapeHtml(company.SourcePersonName || '-')}</div>
                        ${company.SourceProfileUrl ? `<a class="mt-1 block text-xs text-sky-700 hover:underline" href="${escapeHtml(company.SourceProfileUrl)}" target="_blank" rel="noreferrer">Profilo</a>` : ''}
                    </td>
                    <td class="px-4 py-3 max-w-xs">${renderSkillList(skills)}</td>
                    <td class="px-4 py-3">
                        <div class="font-medium">${escapeHtml(category)}</div>
                        ${query ? `<button data-open-query="${escapeHtml(query.Id)}" type="button" class="mt-1 block text-xs text-sky-700 hover:underline">Apri query</button>` : ''}
                    </td>
                    <td class="px-4 py-3 max-w-sm text-slate-600">${escapeHtml(company.Notes || '-')}</td>
                    <td class="px-4 py-3 text-xs text-slate-500">
                        <div>Prima: ${escapeHtml(formatDate(company.FirstSeenAt))}</div>
                        <div class="mt-1">Ultima: ${escapeHtml(formatDate(company.LastSeenAt))}</div>
                    </td>
                    <td class="px-4 py-3 text-right">
                        <div class="flex justify-end gap-2">
                            <button data-edit-company="${escapeHtml(company.Id)}" type="button" class="rounded-md border border-slate-300 px-3 py-1.5 text-xs font-medium hover:bg-slate-100">Edit</button>
                            <button data-delete-company="${escapeHtml(company.Id)}" type="button" class="rounded-md border border-red-200 px-3 py-1.5 text-xs font-medium text-red-700 hover:bg-red-50">Delete</button>
                        </div>
                    </td>
                </tr>
            `;
        }).join('');

        if (companies.length > 0 && filtered.length === 0) {
            elements.companiesTable.innerHTML = '<tr><td colspan="8" class="px-4 py-10 text-center text-slate-500">Nessun risultato con i filtri correnti.</td></tr>';
        }
    }

    function renderAll() {
        initializeFilters();
        updateKpis();
        renderQueries();
        renderCharts();
        renderTable();
    }

    function openCompanyModal(company, searchQuery) {
        const isEdit = Boolean(company);
        elements.companyFormTitle.textContent = isEdit ? 'Modifica azienda' : 'Aggiungi azienda';
        elements.companyId.value = company?.Id || '';
        elements.companyName.value = company?.CompanyName || '';
        elements.companyWebsite.value = company?.Website || '';
        elements.companyPerson.value = company?.SourcePersonName || '';
        elements.companyProfileUrl.value = company?.SourceProfileUrl || '';
        elements.companySkills.value = company?.MatchedSkills || '';
        elements.companySearchQuery.value = company?.SearchQuery || searchQuery || '';
        elements.companyNotes.value = company?.Notes || '';
        elements.companyModal.classList.remove('hidden');
        elements.companyModal.classList.add('flex');
        elements.companyName.focus();
    }

    function closeCompanyModal() {
        elements.companyModal.classList.add('hidden');
        elements.companyModal.classList.remove('flex');
        elements.companyForm.reset();
    }

    function openQueryModal(query) {
        const isEdit = Boolean(query);
        elements.queryFormTitle.textContent = isEdit ? 'Modifica query' : 'Aggiungi query';
        elements.queryId.value = query?.id || '';
        elements.queryCategory.value = query?.category || '';
        elements.queryPriority.value = query?.priority || 1;
        elements.queryTerms.value = Array.isArray(query?.terms) ? query.terms.join('; ') : '';
        elements.queryEnabled.checked = query ? query.enabled !== false : true;
        updateQueryPreview();
        elements.queryModal.classList.remove('hidden');
        elements.queryModal.classList.add('flex');
        elements.queryCategory.focus();
    }

    function closeQueryModal() {
        elements.queryModal.classList.add('hidden');
        elements.queryModal.classList.remove('flex');
        elements.queryForm.reset();
    }

    function updateQueryPreview() {
        elements.queryPreview.textContent = buildQueryText(elements.queryTerms.value);
    }

    async function submitCompany(event) {
        event.preventDefault();
        const id = elements.companyId.value;
        const body = {
            CompanyName: elements.companyName.value,
            Website: elements.companyWebsite.value,
            SourcePersonName: elements.companyPerson.value,
            SourceProfileUrl: elements.companyProfileUrl.value,
            MatchedSkills: elements.companySkills.value,
            SearchQuery: elements.companySearchQuery.value,
            Notes: elements.companyNotes.value
        };
        try {
            const payload = id
                ? await api(`/api/companies/${encodeURIComponent(id)}`, { method: 'PUT', body: JSON.stringify(body) })
                : await api('/api/companies', { method: 'POST', body: JSON.stringify(body) });
            closeCompanyModal();
            updateFromMutation(payload, id ? 'Azienda aggiornata.' : 'Azienda aggiunta.');
        }
        catch (error) {
            showToast(error.message, 'error');
        }
    }

    async function submitQuery(event) {
        event.preventDefault();
        const id = elements.queryId.value;
        const body = {
            category: elements.queryCategory.value,
            priority: elements.queryPriority.value,
            terms: splitValues(elements.queryTerms.value),
            enabled: elements.queryEnabled.checked
        };
        try {
            const payload = id
                ? await api(`/api/queries/${encodeURIComponent(id)}`, { method: 'PUT', body: JSON.stringify(body) })
                : await api('/api/queries', { method: 'POST', body: JSON.stringify(body) });
            closeQueryModal();
            updateFromMutation(payload, id ? 'Query aggiornata.' : 'Query aggiunta.');
        }
        catch (error) {
            showToast(error.message, 'error');
        }
    }

    async function openQuery(id) {
        try {
            await api(`/api/queries/${encodeURIComponent(id)}/open`, { method: 'POST', body: '{}' });
            showToast('Query aperta in una pagina browser separata.', 'success');
        }
        catch (error) {
            showToast(error.message, 'error');
        }
    }

    async function softDeleteCompany(id) {
        const company = companies.find((item) => item.Id === id);
        const label = company?.CompanyName || id;
        if (!window.confirm(`Eliminare "${label}" dalla vista principale? Il record resterà recuperabile in state.json con DeletedAt.`)) {
            return;
        }
        try {
            const payload = await api(`/api/companies/${encodeURIComponent(id)}`, { method: 'DELETE' });
            updateFromMutation(payload, 'Record eliminato con soft delete.');
        }
        catch (error) {
            showToast(error.message, 'error');
        }
    }

    function bindEvents() {
        [elements.textFilter, elements.skillFilter, elements.categoryFilter, elements.websiteFilter].forEach((element) => {
            element.addEventListener('input', renderTable);
            element.addEventListener('change', renderTable);
        });
        elements.resetFilters.addEventListener('click', () => {
            elements.textFilter.value = '';
            elements.skillFilter.value = 'all';
            elements.categoryFilter.value = 'all';
            elements.websiteFilter.value = 'all';
            renderTable();
        });
        elements.refreshDashboard.addEventListener('click', () => loadDashboard().then(() => showToast('Dashboard aggiornata.', 'success')).catch((error) => showToast(error.message, 'error')));
        elements.addCompanyTop.addEventListener('click', () => openCompanyModal(null, ''));
        elements.addQuery.addEventListener('click', () => openQueryModal(null));
        elements.companyForm.addEventListener('submit', submitCompany);
        elements.queryForm.addEventListener('submit', submitQuery);
        elements.queryTerms.addEventListener('input', updateQueryPreview);
        document.querySelectorAll('[data-close-company]').forEach((button) => button.addEventListener('click', closeCompanyModal));
        document.querySelectorAll('[data-close-query]').forEach((button) => button.addEventListener('click', closeQueryModal));

        document.addEventListener('click', (event) => {
            const target = event.target;
            const openQueryId = target.getAttribute('data-open-query');
            const companyFromQueryId = target.getAttribute('data-company-from-query');
            const editQueryId = target.getAttribute('data-edit-query');
            const editCompanyId = target.getAttribute('data-edit-company');
            const deleteCompanyId = target.getAttribute('data-delete-company');

            if (openQueryId) {
                openQuery(openQueryId);
            }
            if (companyFromQueryId) {
                const query = queries.find((item) => item.Id === companyFromQueryId);
                openCompanyModal(null, query?.Query || '');
            }
            if (editQueryId) {
                openQueryModal(profileQueries.find((item) => item.id === editQueryId));
            }
            if (editCompanyId) {
                openCompanyModal(companies.find((item) => item.Id === editCompanyId), '');
            }
            if (deleteCompanyId) {
                softDeleteCompany(deleteCompanyId);
            }
        });
    }

    bindEvents();
    loadDashboard().catch((error) => showToast(error.message, 'error'));
}());
