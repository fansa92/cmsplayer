/// Iterable 小工具，避免为了 `firstWhereOrNull` 再引一个依赖。
extension FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T element) test) {
    for (final T element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}

extension IndexedMap<T> on Iterable<T> {
  Iterable<E> mapIndexed<E>(E Function(int index, T element) toElement) sync* {
    int index = 0;
    for (final T element in this) {
      yield toElement(index, element);
      index++;
    }
  }
}
