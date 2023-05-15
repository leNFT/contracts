const parseSVG = require("svg-parser").parse;

const isValidJSON = (str) => {
  try {
    JSON.parse(str);
    return true;
  } catch (e) {
    console.log(e);
    return false;
  }
};

const isValidSVG = (str) => {
  try {
    parseSVG(str);
    return true;
  } catch (e) {
    console.error(e);
    return false;
  }
};

module.exports = { isValidJSON, isValidSVG };
