class FileTemplates {
  static const String c = '''
#include <stdio.h>

int main(void) {
    printf("Hello, world!\\n");
    return 0;
}
''';

  static const String cpp = '''
#include <iostream>

int main() {
    std::cout << "Hello, world!" << std::endl;
    return 0;
}
''';

  static const String dart = '''
void main() {
  print('Hello, world!');
}
''';

  static const String markdown = '''
# New Document

Start capturing your ideas here.
''';

  static const String python = '''
def main():
    print("Hello, world!")


if __name__ == "__main__":
    main()
''';
}
