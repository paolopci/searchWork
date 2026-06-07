(function () {
    'use strict';

    const data = window.SearchWorkDashboardData || {};
    const state = data.state || {};
    const companies = Array.isArray(state.companies) ? state.companies : [];
    const queries = Array.isArray(data.queries) ? data.queries : [];

    const elements = {
        totalCompanies: document.getElementById('totalCompanies'),
        companiesWithWebsite: document.getElementById('companiesWithWebsite'),
        totalQueries: document.getElementById('totalQueries'),
        stateUpdatedAt: document.getElementById('stateUpdatedAt'),
        snapshotTime: document.getElementById('snapshotTime'),
        lastUpdatedCompact: document.getElementById('lastUpdatedCompact'),
        textFilter: document.getElementById('textFilter'),
        skillFilter: document.getElementById('skillFilter'),
        categoryFilter: document.getElementById('categoryFilter'),
        websiteFilter: document.getElementById('websiteFilter'),
        resetFilters: document.getElementById('resetFilters'),
        resultSummary: document.getElementById('resultSummary'),
        companiesTable: document.getElementById('companiesTable'),
        emptyState: document.getElementById('emptyState'),
        tableWrap: document.getElementById('tableWrap')
    };

    const queryByText = new Map(
        queries
            .filter((query) => query.Query)
            .map((query) => [normalize(query.Query), query])
    );

    function normalize(value) {
        return String(value || '').trim().toLowerCase();
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

    function getCompanyCategory(company) {
        const query = queryByText.get(normalize(company.SearchQuery));
        return query ? query.Category : 'Non classificata';
    }

    function getWebsiteUrl(value) {
        const raw = String(value || '').trim();
        if (!raw) {
            return '';
        }

        return /^[a-z][a-z0-9+\-.]*:\/\//i.test(raw) ? raw : `https://${raw}`;
    }

    function countBy(items, selector) {
        return items.reduce((accumulator, item) => {
            const key = selector(item) || 'Non classificata';
            accumulator.set(key, (accumulator.get(key) || 0) + 1);
            return accumulator;
        }, new Map());
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
        const skills = [...new Set(companies.flatMap((company) => splitValues(company.MatchedSkills)))]
            .sort((a, b) => a.localeCompare(b, 'it', { sensitivity: 'base' }));
        const categories = [...new Set(queries.map((query) => query.Category).filter(Boolean))]
            .sort((a, b) => a.localeCompare(b, 'it', { sensitivity: 'base' }));

        if (companies.some((company) => !queryByText.has(normalize(company.SearchQuery)))) {
            categories.push('Non classificata');
        }

        setOptions(elements.skillFilter, skills, 'Tutte');
        setOptions(elements.categoryFilter, categories, 'Tutte');
    }

    function updateKpis() {
        const withWebsite = companies.filter((company) => String(company.Website || '').trim()).length;
        const updatedAt = state.generatedAt || data.generatedAt;

        elements.totalCompanies.textContent = companies.length;
        elements.companiesWithWebsite.textContent = withWebsite;
        elements.totalQueries.textContent = queries.length;
        elements.stateUpdatedAt.textContent = formatDate(updatedAt);
        elements.snapshotTime.textContent = formatDate(data.generatedAt);
        elements.lastUpdatedCompact.textContent = `Aggiornato: ${formatDate(updatedAt)}`;
    }

    function buildChart(canvasId, type, labels, values, label, colors) {
        const canvas = document.getElementById(canvasId);
        if (!canvas || typeof Chart === 'undefined') {
            return;
        }

        if (labels.length === 0) {
            const container = canvas.parentElement;
            container.innerHTML = '<div class="flex h-full items-center justify-center rounded-md bg-slate-50 text-sm text-slate-500">Nessun dato disponibile</div>';
            return;
        }

        new Chart(canvas, {
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
                        labels: {
                            boxWidth: 12,
                            font: { size: 11 }
                        }
                    }
                },
                scales: type === 'bar' ? {
                    y: {
                        beginAtZero: true,
                        ticks: { precision: 0 }
                    }
                } : {}
            }
        });
    }

    function renderCharts() {
        const palette = ['#0284c7', '#059669', '#7c3aed', '#d97706', '#dc2626', '#475569', '#0891b2', '#65a30d'];
        const categories = countBy(companies, getCompanyCategory);
        const categoryLabels = [...categories.keys()];
        const categoryValues = [...categories.values()];

        const skills = countBy(
            companies.flatMap((company) => splitValues(company.MatchedSkills)),
            (skill) => skill
        );
        const topSkills = [...skills.entries()]
            .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'it', { sensitivity: 'base' }))
            .slice(0, 10);

        buildChart('categoryChart', 'doughnut', categoryLabels, categoryValues, 'Aziende', palette);
        buildChart('skillsChart', 'bar', topSkills.map(([skill]) => skill), topSkills.map(([, count]) => count), 'Occorrenze', palette[0]);
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

            if (text && !haystack.includes(text)) {
                return false;
            }

            if (selectedSkill !== 'all' && !companySkills.some((skill) => skill.toLowerCase() === selectedSkill.toLowerCase())) {
                return false;
            }

            if (selectedCategory !== 'all' && category !== selectedCategory) {
                return false;
            }

            if (websiteMode === 'with' && !hasWebsite) {
                return false;
            }

            if (websiteMode === 'without' && hasWebsite) {
                return false;
            }

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

    function escapeHtml(value) {
        return String(value || '')
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('"', '&quot;')
            .replaceAll("'", '&#039;');
    }

    function renderTable() {
        const filtered = getFilteredCompanies();
        elements.resultSummary.textContent = `${filtered.length} aziende visualizzate su ${companies.length}`;
        elements.emptyState.classList.toggle('hidden', companies.length > 0);
        elements.tableWrap.classList.toggle('hidden', companies.length === 0);

        elements.companiesTable.innerHTML = filtered.map((company) => {
            const websiteUrl = getWebsiteUrl(company.Website);
            const query = queryByText.get(normalize(company.SearchQuery));
            const queryUrl = query ? query.Url : '';
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
                        ${queryUrl ? `<a class="mt-1 block text-xs text-sky-700 hover:underline" href="${escapeHtml(queryUrl)}" target="_blank" rel="noreferrer">Apri query</a>` : ''}
                    </td>
                    <td class="px-4 py-3 max-w-sm text-slate-600">${escapeHtml(company.Notes || '-')}</td>
                    <td class="px-4 py-3 text-xs text-slate-500">
                        <div>Prima: ${escapeHtml(formatDate(company.FirstSeenAt))}</div>
                        <div class="mt-1">Ultima: ${escapeHtml(formatDate(company.LastSeenAt))}</div>
                    </td>
                </tr>
            `;
        }).join('');

        if (companies.length > 0 && filtered.length === 0) {
            elements.companiesTable.innerHTML = `
                <tr>
                    <td colspan="7" class="px-4 py-10 text-center text-slate-500">Nessun risultato con i filtri correnti.</td>
                </tr>
            `;
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
    }

    initializeFilters();
    updateKpis();
    renderCharts();
    bindEvents();
    renderTable();
}());
