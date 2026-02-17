import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/category.dart' as category_model;
import '../services/category_service.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _FilterState {
  final String query;
  final int page;
  const _FilterState({this.query = '', this.page = 1});
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final CategoryService _categoryService = CategoryService();
  final TextEditingController _searchController = TextEditingController();
  final ValueNotifier<_FilterState> _filterNotifier =
      ValueNotifier(const _FilterState());
  static const int _itemsPerPage = 12;

  void _onSearchChanged() {
    _filterNotifier.value = _FilterState(
      query: _searchController.text.trim().toLowerCase(),
      page: 1,
    );
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _filterNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Categories'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddEditCategoryDialog(context),
            tooltip: 'Add Category',
          ),
        ],
      ),
      body: StreamBuilder<List<category_model.Category>>(
        stream: _categoryService.getAllCategoriesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          final categories = snapshot.data ?? [];

          return ValueListenableBuilder<_FilterState>(
            valueListenable: _filterNotifier,
            builder: (context, filter, _) {
              final searchQuery = filter.query;
              final filteredCategories = searchQuery.isEmpty
                  ? categories
                  : categories.where((c) {
                      final nameMatch =
                          c.name.toLowerCase().contains(searchQuery);
                      final descMatch = c.description != null &&
                          c.description!.toLowerCase().contains(searchQuery);
                      return nameMatch || descMatch;
                    }).toList();

              if (filteredCategories.isEmpty) {
                return Column(
                  children: [
                    _buildSearchBar(filter),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              searchQuery.isEmpty
                                  ? Icons.category_outlined
                                  : Icons.search_off,
                              size: 80,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              searchQuery.isEmpty
                                  ? 'No categories yet'
                                  : 'No matching categories',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              searchQuery.isEmpty
                                  ? 'Tap the + button to add your first category'
                                  : 'Try a different search term',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              final totalPages =
                  (filteredCategories.length / _itemsPerPage).ceil();
              final safePage = filter.page.clamp(1, totalPages);
              if (safePage != filter.page && totalPages > 0) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _filterNotifier.value =
                      _FilterState(query: filter.query, page: 1);
                });
              }
              final startIndex = (safePage - 1) * _itemsPerPage;
              final endIndex = (startIndex + _itemsPerPage)
                  .clamp(0, filteredCategories.length);
              final paginatedCategories =
                  filteredCategories.sublist(startIndex, endIndex);

              return Column(
                children: [
                  _buildSearchBar(filter),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: paginatedCategories.length,
                  itemBuilder: (context, index) {
                    final category = paginatedCategories[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                          child: Icon(
                            Icons.category,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        title: Text(
                          category.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: category.isActive
                                ? null
                                : TextDecoration.lineThrough,
                            color: category.isActive
                                ? Colors.black87
                                : Colors.grey,
                          ),
                        ),
                        subtitle: category.description != null && category.description!.isNotEmpty
                            ? Text(
                                category.description!,
                                style: TextStyle(
                                  color: category.isActive
                                      ? Colors.grey[600]
                                      : Colors.grey[400],
                                ),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!category.isActive)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Inactive',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showAddEditCategoryDialog(context, category),
                              tooltip: 'Edit',
                            ),
                            IconButton(
                              icon: Icon(
                                category.isActive ? Icons.delete : Icons.restore,
                                color: category.isActive ? Colors.red : Colors.green,
                              ),
                              onPressed: () => _handleDeleteRestore(category),
                              tooltip: category.isActive ? 'Delete' : 'Restore',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Pagination Controls
              if (totalPages > 1)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 1,
                        blurRadius: 2,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Previous Button
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: safePage > 1
                            ? () {
                                _filterNotifier.value = _FilterState(
                                    query: filter.query, page: safePage - 1);
                              }
                            : null,
                        tooltip: 'Previous',
                      ),
                      const SizedBox(width: 8),
                      // Page Numbers
                      ...List.generate(
                        totalPages > 7 ? 7 : totalPages,
                        (index) {
                          int pageNumber;
                          if (totalPages <= 7) {
                            pageNumber = index + 1;
                          } else {
                            if (safePage <= 4) {
                              pageNumber = index + 1;
                            } else if (safePage >= totalPages - 3) {
                              pageNumber = totalPages - 6 + index;
                            } else {
                              pageNumber = safePage - 3 + index;
                            }
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              onTap: () {
                                _filterNotifier.value = _FilterState(
                                    query: filter.query, page: pageNumber);
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: safePage == pageNumber
                                      ? Colors.blue
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: safePage == pageNumber
                                        ? Colors.blue
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$pageNumber',
                                    style: TextStyle(
                                      color: safePage == pageNumber
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: safePage == pageNumber
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      // Next Button
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: safePage < totalPages
                            ? () {
                                _filterNotifier.value = _FilterState(
                                    query: filter.query, page: safePage + 1);
                              }
                            : null,
                        tooltip: 'Next',
                      ),
                    ],
                  ),
                ),
              // Page Info
              if (totalPages > 1)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: Colors.grey[50],
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Page $safePage of $totalPages',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Showing ${startIndex + 1}-${startIndex + paginatedCategories.length} of ${filteredCategories.length} categories',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
            },
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(_FilterState filter) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search categories...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: filter.query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterNotifier.value = const _FilterState();
                  },
                  tooltip: 'Clear search',
                )
              : null,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  void _showAddEditCategoryDialog(BuildContext context, [category_model.Category? category]) {
    final nameController = TextEditingController(text: category?.name ?? '');
    final descriptionController = TextEditingController(text: category?.description ?? '');
    final formKey = GlobalKey<FormState>();
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? 'Add Category' : 'Edit Category'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Category Name *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    textCapitalization: TextCapitalization.words,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter category name';
                      }
                      return null;
                    },
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      if (formKey.currentState!.validate()) {
                        setDialogState(() {
                          isLoading = true;
                        });

                        try {
                          final categoryToSave = category_model.Category(
                            id: category?.id ?? const Uuid().v4(),
                            name: nameController.text.trim(),
                            description: descriptionController.text.trim().isEmpty
                                ? null
                                : descriptionController.text.trim(),
                            createdAt: category?.createdAt ?? DateTime.now(),
                            updatedAt: DateTime.now(),
                            isActive: category?.isActive ?? true,
                          );

                          if (category == null) {
                            await _categoryService.addCategory(categoryToSave);
                          } else {
                            await _categoryService.updateCategory(categoryToSave);
                          }

                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  category == null
                                      ? 'Category added successfully'
                                      : 'Category updated successfully',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            setDialogState(() {
                              isLoading = false;
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        }
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(category == null ? 'Add' : 'Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDeleteRestore(category_model.Category category) async {
    final isInUse = await _categoryService.isCategoryInUse(category.name);

    if (category.isActive && isInUse) {
      // Warn user if category is in use
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Category in Use'),
          content: Text(
            'This category is currently used by some products. '
            'Deleting it will mark it as inactive, but products will still reference it. '
            'Are you sure you want to continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    } else if (!category.isActive) {
      // Restore category
      final updatedCategory = category.copyWith(
        isActive: true,
        updatedAt: DateTime.now(),
      );
      await _categoryService.updateCategory(updatedCategory);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Category restored successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return;
    }

    // Delete category
    await _categoryService.deleteCategory(category.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Category deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}
