import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_providers.dart';
import '../../data/character_dao.dart';
import '../../domain/character_card.dart';

class CharacterListState {
  const CharacterListState({
    this.items = const <CharacterCard>[],
    this.query = '',
    this.tags = const <String>[],
    this.sort = CardSort.updated,
    this.hasMore = false,
    this.loading = false,
    this.initialized = false,
  });

  final List<CharacterCard> items;
  final String query;
  final List<String> tags;
  final CardSort sort;
  final bool hasMore;
  final bool loading;
  final bool initialized;

  bool get isFiltering => query.isNotEmpty || tags.isNotEmpty;

  CharacterListState copyWith({
    List<CharacterCard>? items,
    String? query,
    List<String>? tags,
    CardSort? sort,
    bool? hasMore,
    bool? loading,
    bool? initialized,
  }) =>
      CharacterListState(
        items: items ?? this.items,
        query: query ?? this.query,
        tags: tags ?? this.tags,
        sort: sort ?? this.sort,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        initialized: initialized ?? this.initialized,
      );
}

class CharacterListController extends Notifier<CharacterListState> {
  static const int pageSize = 30;

  @override
  CharacterListState build() {
    final initial = _fetch(query: '', tags: const <String>[], sort: CardSort.updated);
    return CharacterListState(
      items: initial,
      hasMore: initial.length >= pageSize,
      initialized: true,
    );
  }

  List<CharacterCard> _fetch({
    required String query,
    required List<String> tags,
    required CardSort sort,
    CardCursor? cursor,
  }) {
    return ref.read(characterRepositoryProvider).list(
          query: query,
          tags: tags,
          sort: sort,
          cursor: cursor,
          limit: pageSize,
        );
  }

  void search(String query) {
    state = state.copyWith(query: query);
    _reload();
  }

  void toggleTag(String tag) {
    final next = <String>[...state.tags];
    if (next.contains(tag)) {
      next.remove(tag);
    } else {
      next.add(tag);
    }
    state = state.copyWith(tags: next);
    _reload();
  }

  void clearTags() {
    state = state.copyWith(tags: const <String>[]);
    _reload();
  }

  void setSort(CardSort sort) {
    state = state.copyWith(sort: sort);
    _reload();
  }

  void refresh() => _reload();

  void _reload() {
    final items = _fetch(query: state.query, tags: state.tags, sort: state.sort);
    state = state.copyWith(
      items: items,
      hasMore: items.length >= pageSize,
      loading: false,
    );
  }

  void loadMore() {
    if (state.loading || !state.hasMore || state.items.isEmpty) return;
    final last = state.items.last;
    final cursor = switch (state.sort) {
      CardSort.updated => CardCursor(sortValue: last.updatedAt, id: last.id),
      CardSort.name => CardCursor(sortValue: last.name, id: last.id),
      CardSort.lastChat =>
        CardCursor(sortValue: last.lastChatAt ?? 0, id: last.id),
    };
    final more = _fetch(
      query: state.query,
      tags: state.tags,
      sort: state.sort,
      cursor: cursor,
    );
    state = state.copyWith(
      items: <CharacterCard>[...state.items, ...more],
      hasMore: more.length >= pageSize,
    );
  }

  void removeLocally(String cardId) {
    state = state.copyWith(
      items: state.items.where((c) => c.id != cardId).toList(),
    );
  }
}

final characterListProvider =
    NotifierProvider<CharacterListController, CharacterListState>(
  CharacterListController.new,
);

/// 标签统计（带计数），用于筛选栏
final characterTagsProvider = Provider<List<({String tag, int count})>>((ref) {
  ref.watch(characterListProvider.select((s) => s.items.length));
  return ref.watch(characterRepositoryProvider).tagStats();
});
