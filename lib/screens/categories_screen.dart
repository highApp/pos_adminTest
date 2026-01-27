import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/category.dart' as category_model;
import '../services/category_service.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  final CategoryService _categoryService = CategoryService();
  int _currentPage = 1;
  static const int _itemsPerPage = 12;

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

          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No categories yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the + button to add your first category',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            );
          }

          // Calculate pagination
          final totalPages = (categories.length / _itemsPerPage).ceil();
          final startIndex = (_currentPage - 1) * _itemsPerPage;
          final endIndex = (startIndex + _itemsPerPage).clamp(0, categories.length);
          final paginatedCategories = categories.sublist(startIndex, endIndex);

          // Reset to first page if current page is out of bounds
          if (_currentPage > totalPages && totalPages > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                _currentPage = 1;
              });
            });
          }

          return Column(
            children: [
              // Categories List
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
                        onPressed: _currentPage > 1
                            ? () {
                                setState(() {
                                  _currentPage--;
                                });
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
                            // Show first, last, and pages around current
                            if (_currentPage <= 4) {
                              pageNumber = index + 1;
                            } else if (_currentPage >= totalPages - 3) {
                              pageNumber = totalPages - 6 + index;
                            } else {
                              pageNumber = _currentPage - 3 + index;
                            }
                          }
                          
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _currentPage = pageNumber;
                                });
                              },
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _currentPage == pageNumber
                                      ? Colors.blue
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _currentPage == pageNumber
                                        ? Colors.blue
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    '$pageNumber',
                                    style: TextStyle(
                                      color: _currentPage == pageNumber
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: _currentPage == pageNumber
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
                        onPressed: _currentPage < totalPages
                            ? () {
                                setState(() {
                                  _currentPage++;
                                });
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
                        'Page $_currentPage of $totalPages',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Showing ${startIndex + 1}-${startIndex + paginatedCategories.length} of ${categories.length} categories',
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
