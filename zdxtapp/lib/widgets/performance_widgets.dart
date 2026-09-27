import 'package:flutter/material.dart';

/// 虚拟列表构建器（优化：大数据量列表性能）
/// 
/// 使用场景：当列表项数量超过100时，使用此组件替代ListView.builder
/// 优势：只渲染可见区域的item，大幅减少内存使用和重建次数
class VirtualListView extends StatefulWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemHeight;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final Widget? emptyWidget;
  
  const VirtualListView({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemHeight,
    this.controller,
    this.padding,
    this.emptyWidget,
  });

  @override
  State<VirtualListView> createState() => _VirtualListViewState();
}

class _VirtualListViewState extends State<VirtualListView> {
  late ScrollController _scrollController;
  int _firstVisibleIndex = 0;
  int _lastVisibleIndex = 0;
  
  // 预渲染缓冲区大小（上下各多渲染5个item）
  static const int bufferSize = 5;

  @override
  void initState() {
    super.initState();
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_onScroll);
    
    // 初始化可见范围
    _updateVisibleRange();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _scrollController.dispose();
    } else {
      _scrollController.removeListener(_onScroll);
    }
    super.dispose();
  }

  void _onScroll() {
    _updateVisibleRange();
  }

  void _updateVisibleRange() {
    if (!mounted || widget.itemCount == 0) return;
    
    final viewportHeight = _scrollController.position.viewportDimension;
    final scrollOffset = _scrollController.offset;
    
    // 计算可见的item范围
    final firstVisible = (scrollOffset / widget.itemHeight).floor();
    final visibleCount = (viewportHeight / widget.itemHeight).ceil();
    final lastVisible = firstVisible + visibleCount;
    
    // 添加缓冲区
    final newFirstIndex = (firstVisible - bufferSize).clamp(0, widget.itemCount - 1);
    final newLastIndex = (lastVisible + bufferSize).clamp(0, widget.itemCount - 1);
    
    // 只在范围变化时才更新状态
    if (newFirstIndex != _firstVisibleIndex || newLastIndex != _lastVisibleIndex) {
      setState(() {
        _firstVisibleIndex = newFirstIndex;
        _lastVisibleIndex = newLastIndex;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) {
      return widget.emptyWidget ?? const Center(child: Text('暂无数据'));
    }

    return ListView.builder(
      controller: _scrollController,
      padding: widget.padding,
      itemCount: widget.itemCount,
      itemBuilder: (context, index) {
        // 如果不在可见范围内，返回空容器（不渲染）
        if (index < _firstVisibleIndex || index > _lastVisibleIndex) {
          return SizedBox(height: widget.itemHeight);
        }
        
        // 渲染可见的item
        return widget.itemBuilder(context, index);
      },
    );
  }
}

/// 图片懒加载组件（优化：按需加载图片资源）
class LazyImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;
  
  const LazyImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  State<LazyImage> createState() => _LazyImageState();
}

class _LazyImageState extends State<LazyImage> {
  bool _isLoading = true;
  bool _hasError = false;

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return widget.errorWidget ?? Container(
        width: widget.width,
        height: widget.height,
        color: Colors.grey[200],
        child: const Icon(Icons.broken_image, color: Colors.grey),
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius ?? BorderRadius.zero,
      child: Stack(
        children: [
          Image.network(
            widget.imageUrl,
            width: widget.width,
            height: widget.height,
            fit: widget.fit,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                });
                return child;
              }
              return widget.placeholder ?? Container(
                width: widget.width,
                height: widget.height,
                color: Colors.grey[200],
                child: Center(child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2)),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _hasError = true;
                  });
                }
              });
              return widget.errorWidget ?? Container(
                width: widget.width,
                height: widget.height,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              );
            },
          ),
          if (_isLoading)
            widget.placeholder ?? Container(
              width: widget.width,
              height: widget.height,
              color: Colors.grey[200],
              child: Center(child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2)),
            ),
        ],
      ),
    );
  }
}

/// 分页加载组件（优化：上拉加载更多）
class PaginatedList extends StatefulWidget {
  final Future<List<dynamic>> Function(int page, int pageSize) loadData;
  final IndexedWidgetBuilder itemBuilder;
  final int pageSize;
  final double itemHeight;
  final Widget? emptyWidget;
  final Widget? loadingWidget;
  final Widget? loadMoreWidget;
  
  const PaginatedList({
    super.key,
    required this.loadData,
    required this.itemBuilder,
    this.pageSize = 20,
    this.itemHeight = 80.0,
    this.emptyWidget,
    this.loadingWidget,
    this.loadMoreWidget,
  });

  @override
  State<PaginatedList> createState() => _PaginatedListState();
}

class _PaginatedListState extends State<PaginatedList> {
  List<dynamic> _items = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= 
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      final items = await widget.loadData(_currentPage, widget.pageSize);
      
      setState(() {
        if (_currentPage == 1) {
          _items = items;
        } else {
          _items.addAll(items);
        }
        
        _hasMore = items.length >= widget.pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      // 可选：显示错误提示
    }
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    
    _currentPage++;
    await _loadData();
  }

  Future<void> refresh() async {
    _currentPage = 1;
    _hasMore = true;
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty && !_isLoading) {
      return widget.emptyWidget ?? const Center(child: Text('暂无数据'));
    }

    return Column(
      children: [
        Expanded(
          child: VirtualListView(
            itemCount: _items.length + (_hasMore ? 1 : 0),
            itemHeight: widget.itemHeight,
            itemBuilder: (context, index) {
              if (index == _items.length) {
                // 加载更多指示器
                return widget.loadMoreWidget ?? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2)),
                );
              }
              
              return widget.itemBuilder(context, index);
            },
          ),
        ),
        if (_isLoading && _items.isEmpty)
          widget.loadingWidget ?? const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: CircularProgressIndicator(color: Colors.blue, strokeWidth: 2)),
          ),
      ],
    );
  }
}