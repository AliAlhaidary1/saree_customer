import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_controller.dart';
import '../../core/json_util.dart';
import '../../widgets/app_image.dart';
import '../../widgets/ui_helpers.dart';

void openStoreType(BuildContext context, dynamic category) {
  final id = category is Map ? category['id'] : category;
  if (id == null || '$id'.isEmpty) {
    context.push('/sellers');
    return;
  }
  context.push('/sellers?type=$id');
}

void openCategory(BuildContext context, Map<String, dynamic> category) {
  openStoreType(context, category);
}

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, this.slug = 'all'});
  final String slug;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Map<String, dynamic>> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CategoriesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.slug != widget.slug) _load();
  }

  Future<void> _load() async {
    if (widget.slug != 'all') {
      Map<String, dynamic>? match;
      List<Map<String, dynamic>> walk(dynamic nodes) {
        final out = <Map<String, dynamic>>[];
        for (final node in J.maps(nodes)) {
          out.add(node);
          out.addAll(walk(node['cat_active_childs'] ?? node['children']));
        }
        return out;
      }
      for (final cat in walk(appController.shop?['categories'])) {
        if (J.str(cat['slug']) == widget.slug) {
          match = cat;
          break;
        }
      }
      if (!mounted) return;
      // Web parity: /category/:slug is a real product listing page
      // (CategoryPage), not a sellers redirect.
      if (match != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            context.go('/products?category=${match!['id']}');
          }
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/products');
        });
      }
      return;
    }
    setState(() => loading = true);
    final slug = widget.slug == 'all' ? null : widget.slug;
    final result = await appController.api.categories(
      categoryId: slug == null ? 0 : null,
      slug: slug,
      limit: 50,
      offset: 0,
    );
    if (!mounted) return;
    setState(() {
      items = result.dataMaps;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = appController;
    return Scaffold(
      appBar: AppBar(title: Text(app.t('store_types'))),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
          ? EmptyState(message: app.t('no_categories_found'))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final cat = items[i];
                return InkWell(
                  onTap: () => openCategory(context, cat),
                  borderRadius: BorderRadius.circular(16),
                  child: Ink(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: AppImage(
                              J.str(cat['image_url'] ?? cat['image']),
                              placeholder: app.placeholder,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                          child: Text(
                            J.str(cat['name']),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
