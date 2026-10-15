import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';

import '../../accounts/domain/money_minor.dart';
import '../../categories/domain/category.dart';
import '../domain/csv_document.dart';
import '../domain/csv_import.dart';
import '../domain/csv_profile.dart';
import 'csv_import_cubit.dart';

class CsvPickedFile {
  const CsvPickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

enum CsvPreviewFilter { all, selected, duplicate, invalid }

class CsvImportPage extends StatefulWidget {
  const CsvImportPage({
    super.key,
    required this.repository,
    this.pickFile,
    this.profileStore,
  });
  final CsvImportRepository repository;
  final Future<CsvPickedFile?> Function()? pickFile;
  final CsvProfileStore? profileStore;
  @override
  State<CsvImportPage> createState() => _CsvImportPageState();
}

class _CsvImportPageState extends State<CsvImportPage> {
  late final CsvImportCubit _cubit;
  final _scroll = ScrollController();
  CsvPickedFile? _file;
  CsvDocument? _document;
  CsvMapping _mapping = CsvMapping();
  String? _accountId, _delimiter, _error;
  CsvProfileStore? _profileStore;
  List<CsvProfile> _profiles = [];
  String? _profileName;
  String _bankBalance = '';
  bool _picking = false;
  CsvPreviewFilter _filter = CsvPreviewFilter.all;

  List<(int, CsvPreviewRow)> _visibleRows(CsvImportState state) => [
        for (var i = 0; i < state.rows.length; i++)
          if (switch (_filter) {
            CsvPreviewFilter.all => true,
            CsvPreviewFilter.selected => state.rows[i].selected,
            CsvPreviewFilter.duplicate => state.rows[i].duplicate,
            CsvPreviewFilter.invalid => state.rows[i].error != null,
          })
            (i, state.rows[i]),
      ];
  @override
  void initState() {
    super.initState();
    _cubit = CsvImportCubit(widget.repository)..load();
    _loadProfiles();
  }

  Future<CsvProfileStore> _store() async {
    if (_profileStore != null) return _profileStore!;
    if (widget.profileStore != null) {
      return _profileStore = widget.profileStore!;
    }
    final directory = await getApplicationSupportDirectory();
    return _profileStore ??= CsvProfileStore(
      File('${directory.path}/somia-import-profiles.json'),
    );
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await (await _store()).load();
      if (mounted) setState(() => _profiles = profiles);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Não foi possível ler os perfis locais. Seus dados foram preservados.',
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_document == null || _cubit.state.busy) return;
    final controller = TextEditingController(text: _profileName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Salvar perfil de importação'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(
            labelText: 'Nome do banco ou perfil',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    if (name.isEmpty) {
      setState(() => _error = 'Informe um nome para o perfil.');
      return;
    }
    try {
      final profile = CsvProfile.capture(
        name,
        _delimiter,
        _document!.headers,
        _mapping,
      );
      await (await _store()).save(profile);
      final profiles = await (await _store()).load();
      if (mounted) {
        setState(() {
          _profiles = profiles;
          _profileName = profile.name;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Não foi possível salvar o perfil.',
        );
      }
    }
  }

  void _applyProfile(String? name) {
    if (name == null || _file == null) return;
    if (name.isEmpty) {
      setState(() => _profileName = null);
      return;
    }
    try {
      final profile = _profiles.firstWhere((p) => p.name == name);
      final document = CsvDocument.read(
        _file!.bytes,
        delimiter: profile.delimiter,
      );
      final mapping = profile.apply(document.headers);
      _cubit.reset();
      setState(() {
        _document = document;
        _delimiter = profile.delimiter;
        _mapping = mapping;
        _profileName = name;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<CsvPickedFile?> _nativePick() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (file == null) return null;
    if ((await file.length() ?? 0) > CsvDocument.maxBytes) {
      throw const FormatException('Selecione um CSV de até 2 MB.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      if (bytes.length + chunk.length > CsvDocument.maxBytes) {
        throw const FormatException('Selecione um CSV de até 2 MB.');
      }
      bytes.add(chunk);
    }
    return CsvPickedFile(file.name, bytes.takeBytes());
  }

  Future<void> _pick() async {
    if (_picking || _cubit.state.busy) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final file = await (widget.pickFile?.call() ?? _nativePick());
      if (file == null || !mounted) return;
      _file = file;
      _delimiter = null;
      _profileName = null;
      _parse();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is FormatException
              ? e.message
              : 'Não foi possível ler o CSV. Selecione novamente.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _parse() {
    _cubit.reset();
    setState(() {
      _profileName = null;
      try {
        _document = CsvDocument.read(_file!.bytes, delimiter: _delimiter);
        _mapping = CsvMapping.suggest(_document!.headers);
        _error = null;
      } on FormatException catch (e) {
        _document = null;
        _error = e.message;
      }
    });
  }

  Future<void> _generatePreview() async {
    await _cubit.preview(_document!, _mapping, _accountId!);
    if (mounted) setState(() => _filter = CsvPreviewFilter.all);
    if (mounted && _cubit.state.previewed && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  Future<void> _confirmImport() async {
    final state = _cubit.state;
    if (state.busy || state.selected == 0) return;
    final account = state.references!.accounts.firstWhere(
      (a) => a.id == _accountId,
    );
    final duplicates =
        state.rows.where((r) => r.selected && r.duplicate).length;
    final links =
        state.rows.where((r) => r.selected && r.linkTarget != null).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Importar lançamentos?'),
        content: Text(
          'Serão criados ${state.selected - links} lançamentos e vinculadas $links linhas existentes em ${account.name} (${account.currencyCode}). '
          'Sem data de efetivação, entram como pendentes.'
          '${duplicates == 0 ? '' : '\nVocê selecionou $duplicates possíveis duplicados. Eles também serão adicionados.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _cubit.commit(_accountId!, sourceName: _file?.name ?? 'Extrato');
    }
  }

  Future<void> _chooseMatch(int index) async {
    final row = _cubit.state.rows[index];
    final choice = await showDialog<CsvMatch?>(
        context: context,
        builder: (context) => SimpleDialog(
              title: const Text('Conciliar linha do extrato'),
              children: [
                for (final match in row.matches)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, match),
                    child: Text(
                        '${match.description} • ${match.date.day.toString().padLeft(2, '0')}/${match.date.month.toString().padLeft(2, '0')}/${match.date.year} '
                        '(${switch (match.table) {
                      'transfers' => 'transferência',
                      'card_payments' => 'pagamento de fatura',
                      'transaction_settlements' => 'baixa parcial',
                      _ => 'lançamento'
                    }})'),
                  ),
                SimpleDialogOption(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
              ],
            ));
    if (choice != null && mounted) _cubit.link(index, choice);
  }

  Future<void> _chooseCategory(int index) async {
    final row = _cubit.state.rows[index];
    final categories = _cubit.state.references!.categories
        .where((c) => c.type.name == row.candidate!.type.name)
        .toList();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Escolher categoria'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Sem categoria'),
          ),
          for (final c in categories)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, c.id),
              child: Text(_categoryLabel(c)),
            ),
        ],
      ),
    );
    if (value != null && mounted) {
      _cubit.category(index, value.isEmpty ? null : value);
    }
  }

  String _categoryLabel(FinanceCategory category) {
    final parents = _cubit.state.references!.categories.where(
      (c) => c.id == category.parentId,
    );
    return parents.isEmpty
        ? category.name
        : '${parents.first.name} › ${category.name}';
  }

  Widget _column(
    String title,
    int? value,
    void Function(int?) change, {
    bool required = false,
  }) {
    final headers = _document!.headers;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int>(
        key: ValueKey('$title:$value:${_document.hashCode}'),
        initialValue: value ?? -1,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: required ? '$title *' : title,
          helperText: value == null
              ? null
              : 'Exemplo: ${_document!.rows.first.cells.length > value ? _document!.rows.first.cells[value] : '—'}',
          helperMaxLines: 2,
        ),
        items: [
          DropdownMenuItem(
            value: -1,
            child: Text(required ? 'Escolha uma coluna' : 'Não usar'),
          ),
          for (var i = 0; i < headers.length; i++)
            DropdownMenuItem(
              value: i,
              child: Text(
                '${i + 1}. ${headers[i]}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _cubit.state.busy
            ? null
            : (v) => setState(() => change(v == -1 ? null : v)),
      ),
    );
  }

  Widget _options(CsvImportState state) {
    final refs = state.references;
    final accounts = refs?.accounts ?? [];
    if (_accountId == null && accounts.isNotEmpty) {
      _accountId = accounts.first.id;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '1. Arquivo CSV',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Importe receitas e despesas de uma conta. Confira tudo na prévia antes de confirmar. Até 2 MB e 5.000 linhas.',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: state.busy || _picking ? null : _pick,
          icon: const Icon(Icons.upload_file),
          label: Text(_file == null ? 'Selecionar CSV' : 'Trocar arquivo'),
        ),
        if (_file != null) ...[
          Text(_file!.name),
          if (_profiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('profile:$_profileName:${_file.hashCode}'),
              initialValue: _profileName ?? '',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Perfil do banco'),
              items: [
                const DropdownMenuItem(
                  value: '',
                  child: Text('Escolha um perfil'),
                ),
                for (final profile in _profiles)
                  DropdownMenuItem(
                    value: profile.name,
                    child: Text(profile.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: state.busy ? null : (v) => _applyProfile(v),
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('separator:${_file.hashCode}:$_delimiter'),
            initialValue: _delimiter ?? 'auto',
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Separador'),
            items: const [
              DropdownMenuItem(value: 'auto', child: Text('Automático')),
              DropdownMenuItem(
                value: ';',
                child: Text(
                  'Ponto e vírgula (;)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: ',',
                child: Text(
                  'Vírgula (,)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: '\t',
                child: Text(
                  'Tabulação',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: state.busy
                ? null
                : (v) {
                    _delimiter = v == 'auto' ? null : v;
                    _parse();
                  },
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_document != null && refs != null) ...[
          const SizedBox(height: 16),
          Text('${_document!.rows.length} linhas • ${_document!.encoding}'),
          const SizedBox(height: 16),
          const Text(
            '2. Conta e colunas',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (accounts.isEmpty)
            const Text('Cadastre uma conta ativa antes de importar.'),
          if (accounts.isNotEmpty)
            DropdownButtonFormField<String>(
              initialValue: _accountId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Conta de destino'),
              items: accounts
                  .map(
                    (a) => DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.name} (${a.currencyCode})',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged:
                  state.busy ? null : (v) => setState(() => _accountId = v),
            ),
          const SizedBox(height: 16),
          _column(
            'Descrição',
            _mapping.description,
            (v) => _mapping.description = v,
            required: true,
          ),
          _column(
            'Valor',
            _mapping.amount,
            (v) => _mapping.amount = v,
            required: true,
          ),
          DropdownButtonFormField<CsvAmountFormat>(
            key: ValueKey(_mapping.amountFormat),
            initialValue: _mapping.amountFormat,
            decoration: const InputDecoration(labelText: 'Formato dos valores'),
            isExpanded: true,
            items: const [
              DropdownMenuItem(
                value: CsvAmountFormat.comma,
                child: Text(
                  '1.234,56 (vírgula decimal)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: CsvAmountFormat.dot,
                child: Text(
                  '1,234.56 (ponto decimal)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: state.busy
                ? null
                : (v) => setState(() => _mapping.amountFormat = v!),
          ),
          const SizedBox(height: 16),
          _column(
            'Data de lançamento',
            _mapping.date,
            (v) => _mapping.date = v,
            required: true,
          ),
          DropdownButtonFormField<CsvDateFormat>(
            key: ValueKey(_mapping.dateFormat),
            initialValue: _mapping.dateFormat,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Formato das datas'),
            items: const [
              DropdownMenuItem(
                value: CsvDateFormat.dayFirst,
                child: Text('DD/MM/AAAA'),
              ),
              DropdownMenuItem(
                value: CsvDateFormat.iso,
                child: Text('AAAA-MM-DD'),
              ),
              DropdownMenuItem(
                value: CsvDateFormat.monthFirst,
                child: Text('MM/DD/AAAA'),
              ),
            ],
            onChanged: state.busy
                ? null
                : (v) => setState(() => _mapping.dateFormat = v!),
          ),
          const SizedBox(height: 16),
          _column('Vencimento', _mapping.due, (v) => _mapping.due = v),
          _column(
            'Efetivação',
            _mapping.effective,
            (v) => _mapping.effective = v,
          ),
          const Text(
            'Você pode escolher a mesma coluna para as três datas. Sem vencimento: usa o lançamento. Sem efetivação: fica pendente.',
          ),
          const SizedBox(height: 16),
          _column(
            'Tipo (receita ou despesa)',
            _mapping.type,
            (v) => _mapping.type = v,
          ),
          if (_mapping.type == null)
            DropdownButtonFormField<CsvDirection>(
              key: ValueKey(_mapping.direction),
              initialValue: _mapping.direction,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Tipo dos lançamentos',
              ),
              items: const [
                DropdownMenuItem(
                  value: CsvDirection.signed,
                  child: Text(
                    'Pelo sinal: + receita, − despesa',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownMenuItem(
                  value: CsvDirection.income,
                  child: Text('Todas receitas'),
                ),
                DropdownMenuItem(
                  value: CsvDirection.expense,
                  child: Text('Todas despesas'),
                ),
              ],
              onChanged: state.busy
                  ? null
                  : (v) => setState(() => _mapping.direction = v!),
            ),
          const SizedBox(height: 16),
          _column('Categoria', _mapping.category, (v) => _mapping.category = v),
          _column(
            'Subcategoria',
            _mapping.subcategory,
            (v) => _mapping.subcategory = v,
          ),
          const Text(
            'Categorias existentes são associadas pelo nome. Sem categoria no arquivo, usamos sugestões do histórico; você pode alterar na prévia.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: state.busy ? null : _saveProfile,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Salvar colunas como perfil'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: state.busy || accounts.isEmpty ? null : _generatePreview,
            child: const Text('Gerar prévia'),
          ),
        ],
        if (state.references == null && !state.busy)
          TextButton(
            onPressed: _cubit.load,
            child: const Text('Tentar novamente'),
          ),
      ],
    );
  }

  Widget _previewHeader(CsvImportState state) {
    final account =
        state.references!.accounts.firstWhere((a) => a.id == _accountId);
    var income = 0, expense = 0;
    var balanceAfter = account.currentBalanceMinor;
    final now = DateTime.now();
    final tomorrow = DateTime.utc(now.year, now.month, now.day + 1);
    for (final row in state.rows.where((r) => r.selected)) {
      final candidate = row.candidate!;
      if (candidate.type.name == 'income') {
        income += candidate.amountMinor;
      } else {
        expense += candidate.amountMinor;
      }
      final effective = candidate.effectiveDate;
      if (row.linkTarget == null &&
          effective != null &&
          effective.isBefore(tomorrow)) {
        balanceAfter += candidate.type.name == 'income'
            ? candidate.amountMinor
            : -candidate.amountMinor;
      }
    }
    int? bankMinor;
    if (_bankBalance.trim().isNotEmpty) {
      try {
        bankMinor = MoneyMinor.parse(_bankBalance);
      } on FormatException {
        bankMinor = null;
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '3. Conferir lançamentos',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Conta: ${account.name} • Arquivo: ${_file?.name ?? 'Extrato'}',
        ),
        const SizedBox(height: 8),
        Text(
          '${state.selected} selecionados • ${state.rows.where((r) => r.duplicate).length} possíveis duplicados • ${state.rows.where((r) => r.error != null).length} linhas inválidas',
        ),
        Text(
            'Selecionados: receitas ${MoneyMinor.display(income, account.currencyCode)} '
            '• despesas ${MoneyMinor.display(expense, account.currencyCode)}'),
        const SizedBox(height: 8),
        Text('Saldo Somia após confirmar os lançamentos efetivados até hoje: '
            '${MoneyMinor.display(balanceAfter, account.currencyCode)}'),
        TextField(
          keyboardType: const TextInputType.numberWithOptions(
              decimal: true, signed: true),
          decoration: const InputDecoration(
              labelText: 'Saldo atual informado pelo banco (opcional)',
              helperText:
                  'Compare um extrato atualizado até hoje; use 123,45.'),
          onChanged: (value) => setState(() => _bankBalance = value),
        ),
        if (_bankBalance.isNotEmpty && bankMinor == null)
          const Text('Saldo inválido. Informe até duas casas decimais.'),
        if (bankMinor != null)
          Text('Diferença banco − Somia: '
              '${MoneyMinor.display(bankMinor - balanceAfter, account.currencyCode)}'),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (final (filter, label) in [
            (CsvPreviewFilter.all, 'Todas'),
            (CsvPreviewFilter.selected, 'Selecionadas'),
            (CsvPreviewFilter.duplicate, 'Duplicadas'),
            (CsvPreviewFilter.invalid, 'Inválidas')
          ])
            ChoiceChip(
                label: Text(label),
                selected: _filter == filter,
                onSelected: (_) => setState(() => _filter = filter)),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Duplicados ficam desmarcados. Marque apenas se quiser adicionar outro lançamento igual. Linhas inválidas não serão importadas.',
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: state.busy ? null : () => _cubit.selectNew(true),
              child: const Text('Selecionar novos'),
            ),
            TextButton(
              onPressed: state.busy ? null : () => _cubit.selectNew(false),
              child: const Text('Desmarcar todos'),
            ),
            TextButton(
              onPressed: state.busy ? null : _cubit.reset,
              child: const Text('Ajustar colunas'),
            ),
          ],
        ),
        FilledButton(
          onPressed: state.busy || state.selected == 0 ? null : _confirmImport,
          child: Text('Importar ${state.selected} lançamentos'),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _row(CsvPreviewRow row, int index, CsvImportState state) {
    final candidate = row.candidate;
    final categories = state.references!.categories.where(
      (c) => c.id == row.categoryId,
    );
    final currency = state.references!.accounts
        .firstWhere((a) => a.id == _accountId)
        .currencyCode;
    String date(DateTime d) =>
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: row.selected,
            onChanged: state.busy || candidate == null
                ? null
                : (v) => _cubit.select(index, v!),
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(candidate?.description ?? 'Linha ${row.line} inválida'),
            subtitle: Text(
              candidate == null
                  ? row.error!
                  : 'Linha ${row.line} • ${candidate.type.label} • ${MoneyMinor.display(candidate.amountMinor, currency)}\nLançamento: ${date(candidate.date)} • Vencimento: ${date(candidate.dueDate)}\n${candidate.effectiveDate == null ? 'Pendente' : 'Efetivação: ${date(candidate.effectiveDate!)}'}',
            ),
          ),
          if (row.duplicate)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Possível duplicado no arquivo ou na conta'),
            ),
          if (row.warning != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(row.warning!),
            ),
          if (row.linkTarget != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child:
                  Text('Vincular ao registro: ${row.linkTarget!.description}'),
            ),
          if (candidate != null && row.matches.isNotEmpty)
            Wrap(children: [
              TextButton(
                  onPressed: state.busy ? null : () => _chooseMatch(index),
                  child: Text('Conciliar (${row.matches.length} sugestões)')),
              if (row.linkTarget != null)
                TextButton(
                    onPressed: state.busy
                        ? null
                        : () {
                            _cubit.link(index, null);
                            _cubit.select(index, true);
                          },
                    child: const Text('Criar novo lançamento')),
            ]),
          if (candidate != null)
            TextButton(
              onPressed: state.busy ? null : () => _chooseCategory(index),
              child: Text(
                categories.isEmpty
                    ? 'Sem categoria — escolher'
                    : _categoryLabel(categories.first),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<CsvImportCubit, CsvImportState>(
        bloc: _cubit,
        listener: (context, state) {
          if (state.result != null) Navigator.pop(context, state.result);
        },
        builder: (context, state) {
          final visible = state.previewed
              ? _visibleRows(state)
              : const <(int, CsvPreviewRow)>[];
          return PopScope(
            canPop: !state.busy && !_picking,
            child: Scaffold(
              appBar: AppBar(title: const Text('Importar CSV')),
              body: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(20),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (state.previewed)
                                _previewHeader(state)
                              else
                                _options(state),
                              if (state.error != null)
                                Text(
                                  state.error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              if (state.busy || _picking)
                                const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (state.previewed)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          sliver: SliverList.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, i) =>
                                _row(visible[i].$2, visible[i].$1, state),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
}
