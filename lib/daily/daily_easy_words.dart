// Sprout words (spec-06): for each Daily theme, eight short hidden words
// (3 or 4 letters) with a meaning a young reader can follow. Bundled, so
// a Sprout puzzle never needs the network. Keyed by DailyTheme.id.
// test/word_levels_test.dart checks every word is in the game dictionary,
// is not a magic word, and that no meaning gives its word away.
class EasyWord {
  final String word; // uppercase
  final String meaning;

  const EasyWord(this.word, this.meaning);
}

const Map<String, List<EasyWord>> kEasyWords = {
  'animals': [
    EasyWord('CAT', 'A furry pet that purrs.'),
    EasyWord('DOG', 'A pet that barks and wags its tail.'),
    EasyWord('PIG', 'A pink farm animal that says oink.'),
    EasyWord('COW', 'A big farm animal that gives milk.'),
    EasyWord('HEN', 'A mother chicken. She lays eggs.'),
    EasyWord('FOX', 'A wild animal with red fur and a bushy tail.'),
    EasyWord('BEE', 'A buzzing insect that makes honey.'),
    EasyWord('DUCK', 'A bird that swims and says quack.'),
  ],
  'food': [
    EasyWord('EGG', 'It has a shell. You can fry it or boil it.'),
    EasyWord('PIE', 'A baked treat with a crust and a filling.'),
    EasyWord('JAM', 'Sweet fruit spread for toast.'),
    EasyWord('HAM', 'Pink meat, often in a sandwich.'),
    EasyWord('CORN', 'Yellow kernels that grow on a cob.'),
    EasyWord('RICE', 'Small white grains you cook in water.'),
    EasyWord('MILK', 'A white drink that comes from cows.'),
    EasyWord('SOUP', 'A warm meal you eat with a spoon.'),
  ],
  'garden': [
    EasyWord('ROSE', 'A flower with a sweet smell and thorns.'),
    EasyWord('SEED', 'A plant grows from this tiny thing.'),
    EasyWord('LEAF', 'A flat green part of a plant.'),
    EasyWord('TREE', 'A tall plant with a trunk and branches.'),
    EasyWord('BUD', 'A flower before it opens.'),
    EasyWord('SOIL', 'The dirt that plants grow in.'),
    EasyWord('WEED', 'A wild plant growing where you do not want it.'),
    EasyWord('POT', 'A container to grow a plant in.'),
  ],
  'weather': [
    EasyWord('RAIN', 'Water that falls from the clouds in drops.'),
    EasyWord('SNOW', 'Soft white flakes that fall when it is cold.'),
    EasyWord('WIND', 'Moving air you can feel but not see.'),
    EasyWord('SUN', 'It shines in the sky and warms the day.'),
    EasyWord('FOG', 'A cloud close to the ground.'),
    EasyWord('HAIL', 'Small balls of ice that fall from the sky.'),
    EasyWord('ICE', 'Water that is frozen hard.'),
    EasyWord('HOT', 'Very warm, like a summer day.'),
  ],
  'home': [
    EasyWord('BED', 'You sleep in it at night.'),
    EasyWord('RUG', 'A soft mat on the floor.'),
    EasyWord('LAMP', 'It gives light in a room.'),
    EasyWord('DOOR', 'You open it to go in or out.'),
    EasyWord('SOFA', 'A long soft seat for a few people.'),
    EasyWord('SINK', 'A bowl with taps for washing.'),
    EasyWord('ROOF', 'The top of a building. It keeps the rain out.'),
    EasyWord('WALL', 'A side of a room. Pictures hang on it.'),
  ],
  'music': [
    EasyWord('SONG', 'Words and music that you can sing.'),
    EasyWord('TUNE', 'A string of notes that sounds nice.'),
    EasyWord('DRUM', 'You hit it with sticks to make a beat.'),
    EasyWord('HORN', 'You blow into it to make a loud sound.'),
    EasyWord('BELL', 'It rings when you shake it.'),
    EasyWord('HUM', 'To make music with your lips closed.'),
    EasyWord('SING', 'To make music with your voice.'),
    EasyWord('NOTE', 'One single sound in music.'),
  ],
  'clothes': [
    EasyWord('HAT', 'You wear it on your head.'),
    EasyWord('SOCK', 'It keeps one foot warm inside a shoe.'),
    EasyWord('COAT', 'You wear it over your clothes to stay warm.'),
    EasyWord('VEST', 'A top with no sleeves.'),
    EasyWord('BELT', 'It goes around your waist to hold up pants.'),
    EasyWord('SHOE', 'You wear it on your foot to walk outside.'),
    EasyWord('CAP', 'A soft hat with a brim at the front.'),
    EasyWord('TIE', 'A long strip of cloth worn around the neck.'),
  ],
  'sea': [
    EasyWord('SAND', 'Tiny grains that cover a beach.'),
    EasyWord('BOAT', 'It floats and carries people over water.'),
    EasyWord('TIDE', 'The sea rising and falling each day.'),
    EasyWord('FISH', 'An animal that swims and has fins.'),
    EasyWord('CRAB', 'A sea animal with a shell and two claws.'),
    EasyWord('WAVE', 'Water that rolls onto the shore.'),
    EasyWord('SHIP', 'A very big boat.'),
    EasyWord('SEAL', 'A sea animal with flippers that barks.'),
  ],
};
