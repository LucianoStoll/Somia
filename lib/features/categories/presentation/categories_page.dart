import 'category_visuals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/injection.dart';
import '../../../core/widgets/unsaved_changes_guard.dart';
import '../../../core/widgets/movement_form_frame.dart';
import '../../../core/routing/somia_shell.dart';
import '../domain/categories_repository.dart';
import '../domain/category.dart';
import 'categories_cubit.dart';

const _icons = <String, IconData>{
  'shopping': Icons.shopping_bag_outlined,
  'food': Icons.restaurant_outlined,
  'home': Icons.home_outlined,
  'transport': Icons.directions_car_outlined,
  'work': Icons.work_outline,
  'other': Icons.label_outline,
};

const _colors = <int, String>{
  0xff1976d2: 'Azul',
  0xff388e3c: 'Verde',
  0xffef6c00: 'Laranja',
  0xff7b1fa2: 'Roxo',
  0xffc62828: 'Vermelho',
  0xff455a64: 'Cinza',
};

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (_) => CategoriesCubit(getIt<CategoriesRepository>()),
        child: const _CategoriesView(),
      );
}

class _CategoriesView extends StatefulWidget {
  const _CategoriesView();

  @override
  State<_CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<_CategoriesView> {
  CategoryType _filter = CategoryType.expense;
  final Set<String> _collapsed = {};

  Future<void> _edit(
      [FinanceCategory? category, FinanceCategory? parent]) async {
    final categories = context.read<CategoriesCubit>().state.categories;
    final draft = await showMovementForm<CategoryDraft>(
      context,
      (_) => CategoryForm(
          category: category,
          categories: categories,
          defaultType: parent?.type ?? _filter,
          parent: parent),
    );
    if (draft == null || !mounted) return;
    try {
      await context.read<CategoriesCubit>().save(draft, id: category?.id);
      if (parent != null && mounted) {
        setState(() => _collapsed.remove(parent.id));
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _archive(FinanceCategory category) async {
    try {
      await context.read<CategoriesCubit>().setArchived(category);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    final message = error is FormatException
        ? error.message
        : error is StateError
            ? error.message
            : 'Não foi possível salvar a categoria.';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Categorias'),
          leading: somiaMenuLeading(context),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _edit,
          icon: const Icon(Icons.add),
          label: const Text('Nova categoria'),
        ),
        body: BlocBuilder<CategoriesCubit, CategoriesState>(
          builder: (context, state) {
            if (state.loading && state.categories.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.error != null) {
              return Center(
                  child: TextButton(
                onPressed: context.read<CategoriesCubit>().load,
                child: Text('${state.error} Tentar novamente'),
              ));
            }
            final roots = state.categories
                .where(
                  (category) =>
                      category.type == _filter && !category.isSubcategory,
                )
                .toList();
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<CategoryType>(
                    segments: CategoryType.values
                        .map((type) => ButtonSegment(
                              value: type,
                              label: Text(type.label),
                            ))
                        .toList(),
                    selected: {_filter},
                    onSelectionChanged: (selection) =>
                        setState(() => _filter = selection.first),
                  ),
                ),
                Expanded(
                  child: roots.isEmpty
                      ? const Center(
                          child: Text('Nenhuma categoria cadastrada.'))
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                          children: [
                            for (final root in roots) ...[
                              _categoryTile(root),
                              if (!_collapsed.contains(root.id))
                                for (final child in state.categories.where(
                                    (category) => category.parentId == root.id))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 28),
                                    child: _categoryTile(child),
                                  ),
                            ],
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      );

  Widget _categoryTile(FinanceCategory category) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: Icon(_icons[category.iconKey] ?? Icons.label_outline,
              color: categoryDisplayColor(category)),
          title:
              Text(category.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(category.isArchived
              ? 'Arquivada · histórico preservado'
              : category.isSubcategory
                  ? 'Subcategoria'
                  : 'Categoria principal'),
          onTap: () => _edit(category),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (!category.isSubcategory) ...[
              IconButton(
                  key: ValueKey('category-expand-${category.id}'),
                  tooltip: _collapsed.contains(category.id)
                      ? 'Mostrar subcategorias'
                      : 'Ocultar subcategorias',
                  onPressed: () => setState(() {
                        if (!_collapsed.add(category.id)) {
                          _collapsed.remove(category.id);
                        }
                      }),
                  icon: Icon(_collapsed.contains(category.id)
                      ? Icons.expand_more
                      : Icons.expand_less)),
              if (!category.isArchived)
                IconButton(
                    key: ValueKey('category-add-${category.id}'),
                    tooltip: 'Adicionar subcategoria',
                    onPressed: () => _edit(null, category),
                    icon: const Icon(Icons.add)),
            ],
            PopupMenuButton<String>(
              tooltip: 'Ações da categoria',
              onSelected: (action) =>
                  action == 'edit' ? _edit(category) : _archive(category),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Editar')),
                PopupMenuItem(
                    value: 'archive',
                    child: Text(category.isArchived ? 'Reativar' : 'Arquivar')),
              ],
            ),
          ]),
        ),
      );
}

class CategoryForm extends StatefulWidget {
  const CategoryForm(
      {super.key,
      required this.categories,
      required this.defaultType,
      this.category,
      this.parent});
  final FinanceCategory? category;
  final FinanceCategory? parent;
  final List<FinanceCategory> categories;
  final CategoryType defaultType;

  @override
  State<CategoryForm> createState() => CategoryFormState();
}

class CategoryFormState extends State<CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late CategoryType _type;
  String? _parentId;
  String _iconKey = 'other';
  int _colorArgb = 0xff1976d2;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _type = widget.category?.type ?? widget.parent?.type ?? widget.defaultType;
    _parentId = widget.category?.parentId ?? widget.parent?.id;
    _iconKey = widget.category?.iconKey ?? 'other';
    _colorArgb = widget.category?.colorArgb ?? 0xff1976d2;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
        context,
        CategoryDraft(
          name: _name.text.trim(),
          type: _type,
          parentId: _parentId,
          iconKey: _iconKey,
          colorArgb: _colorArgb,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final parents = widget.categories
        .where((category) =>
            category.type == _type &&
            !category.isSubcategory &&
            (!category.isArchived || category.id == _parentId) &&
            category.id != widget.category?.id)
        .toList();
    return UnsavedChangesGuard(
        value: () => (_name.text, _type, _parentId, _iconKey, _colorArgb),
        builder: (context, cancel) => MovementFormFrame(
              onCancel: cancel,
              onSave: _submit,
              saveLabel: 'Salvar categoria',
              title: widget.category == null
                  ? (widget.parent == null
                      ? 'Nova categoria'
                      : 'Nova subcategoria')
                  : widget.category!.isSubcategory
                      ? 'Editar subcategoria'
                      : 'Editar categoria',
              child: Form(
                key: _formKey,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 16,
                    children: [
                      TextFormField(
                        controller: _name,
                        autofocus: widget.category == null &&
                            usesFullScreenMovementForm(context),
                        textInputAction: TextInputAction.next,
                        scrollPadding: const EdgeInsets.all(100),
                        decoration: const InputDecoration(labelText: 'Nome'),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                                ? 'Informe o nome.'
                                : null,
                      ),
                      DropdownButtonFormField<CategoryType>(
                        menuMaxHeight: 280,
                        borderRadius: BorderRadius.circular(16),
                        itemHeight: 48,
                        isExpanded: true,
                        initialValue: _type,
                        decoration: const InputDecoration(labelText: 'Tipo'),
                        items: CategoryType.values
                            .map((type) => DropdownMenuItem(
                                  value: type,
                                  child: Text(type.label),
                                ))
                            .toList(),
                        onChanged: (type) {
                          if (type != null) {
                            setState(() {
                              _type = type;
                              _parentId = null;
                            });
                          }
                        },
                      ),
                      DropdownButtonFormField<String>(
                        menuMaxHeight: 280,
                        borderRadius: BorderRadius.circular(16),
                        itemHeight: 48,
                        isExpanded: true,
                        key: ValueKey(_type),
                        initialValue: _parentId,
                        decoration: const InputDecoration(
                            labelText: 'Categoria principal'),
                        hint: const Text('Nenhuma (categoria principal)'),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('Nenhuma')),
                          for (final parent in parents)
                            DropdownMenuItem(
                                value: parent.id,
                                child: Text(parent.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (id) => setState(() =>
                            _parentId = id == null || id.isEmpty ? null : id),
                      ),
                      DropdownButtonFormField<String>(
                        menuMaxHeight: 280,
                        borderRadius: BorderRadius.circular(16),
                        itemHeight: 48,
                        isExpanded: true,
                        initialValue: _iconKey,
                        decoration: const InputDecoration(labelText: 'Ícone'),
                        items: _icons.entries
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(entry.value),
                                        const SizedBox(width: 8),
                                        Text(entry.key),
                                      ]),
                                ))
                            .toList(),
                        onChanged: (key) {
                          if (key != null) setState(() => _iconKey = key);
                        },
                      ),
                      DropdownButtonFormField<int>(
                        menuMaxHeight: 280,
                        borderRadius: BorderRadius.circular(16),
                        itemHeight: 48,
                        isExpanded: true,
                        initialValue: _colorArgb,
                        decoration: const InputDecoration(labelText: 'Cor'),
                        items: _colors.entries
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.circle,
                                            color: Color(entry.key)),
                                        const SizedBox(width: 8),
                                        Text(entry.value),
                                      ]),
                                ))
                            .toList(),
                        onChanged: (color) {
                          if (color != null) {
                            setState(() => _colorArgb = color);
                          }
                        },
                      ),
                    ]),
              ),
            ));
  }
}
